//
//  MapViewModel.swift
//  Wheel Routes
//

import Foundation
import CoreLocation
import Observation

enum WaypointRole: Equatable { case from, to }

/// A place selected outside `MapView`'s own search flow (e.g. from
/// Saved Locations), paired with which waypoint it should fill.
struct PendingPlaceSelection: Equatable {
    let place: Place
    let role: WaypointRole
}

/// One of the three concurrently-fetched route plans shown on the map at
/// once. `journey` is nil and `errorMessage` is set when that plan's
/// request failed.
struct RouteOption: Identifiable, Equatable {
    var id: RoutePlan { plan }
    let plan: RoutePlan
    var journey: Journey?
    var errorMessage: String?

    /// True when this plan's request failed (no journey to show).
    var failed: Bool { journey == nil }
}

@Observable
@MainActor
final class MapViewModel {
    var searchResults: [Place] = []
    var fromPlace: Place?
    var toPlace: Place?
    var routeOptions: [RouteOption] = []
    var selectedPlan: RoutePlan
    var isLoading = false
    var errorMessage: String?
    var isPresentingLocationPermissionAlert = false
    var searchDebounceMilliseconds: UInt64 = 300

    /// The active route among `routeOptions` — feeds `ItineraryView`, Save, and GPX export.
    var currentJourney: Journey? { routeOptions.first { $0.plan == selectedPlan }?.journey }

    /// Non-prompting read of whether location access is already granted —
    /// used by `MapView` to gate passive map auto-centering so it never
    /// triggers the system permission prompt at launch.
    var isLocationAuthorized: Bool { locationService.isAuthorized }

    private let apiClient: any APIClientProtocol
    private let locationService: any LocationServiceProtocol
    private let searchProvider: any LocationSearchProviding
    private var searchDebounceTask: Task<Void, Never>?

    /// Best-effort location bias for `search(query:)`, populated by
    /// `loadBiasCoordinateIfAuthorized()` if location access is already
    /// authorized (never prompts). Deliberately not `private` — tests poll
    /// it directly to know when the background fetch has completed.
    var biasCoordinate: CLLocationCoordinate2D?

    init(apiClient: any APIClientProtocol, locationService: any LocationServiceProtocol, searchProvider: any LocationSearchProviding, initialSelectedPlan: RoutePlan = .balanced) {
        self.apiClient = apiClient
        self.locationService = locationService
        self.searchProvider = searchProvider
        self.selectedPlan = initialSelectedPlan
    }

    /// Best-effort, one-shot: bias search results toward the device's location
    /// if it's already authorized. Never triggers the permission prompt itself.
    /// Call this once from the owning view's lifecycle (not from init — init
    /// runs on every reconstruction of a throwaway MapViewModel value, even
    /// when @State discards it, so a side effect there would fire repeatedly).
    func loadBiasCoordinateIfAuthorized() {
        guard locationService.isAuthorized else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let coordinate = try? await self.locationService.currentLocation() else { return }
            self.biasCoordinate = coordinate
        }
    }

    func search(query: String) async {
        guard !query.isEmpty else { searchResults = []; return }
        do {
            searchResults = try await searchProvider.search(query: query, near: biasCoordinate)
        } catch {
            // A newer keystroke may have cancelled this in-flight request via
            // searchTextChanged's debounce; that's not a user-facing error.
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Called as the user types in the search field to provide typeahead
    /// suggestions, debouncing so each keystroke doesn't fire its own
    /// network request.
    func searchTextChanged(_ text: String) {
        searchDebounceTask?.cancel()
        guard !text.isEmpty else { searchResults = []; return }
        let milliseconds = searchDebounceMilliseconds
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard !Task.isCancelled else { return }
            await search(query: text)
        }
    }

    /// Fetches all 3 route plans concurrently and shows them together. If
    /// the currently selected plan's request fails but another succeeds,
    /// falls back to the first successful plan in quietest/balanced/fastest
    /// order, so a partially-successful fetch never leaves nothing selected.
    func planRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async {
        isLoading = true
        async let quietest = fetchOption(.quietest, from: from, to: to)
        async let balanced = fetchOption(.balanced, from: from, to: to)
        async let fastest = fetchOption(.fastest, from: from, to: to)
        routeOptions = [await quietest, await balanced, await fastest]
        if routeOptions.first(where: { $0.plan == selectedPlan })?.journey == nil,
           let fallback = routeOptions.first(where: { $0.journey != nil }) {
            selectedPlan = fallback.plan
        }
        isLoading = false
    }

    private func fetchOption(_ plan: RoutePlan, from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) async -> RouteOption {
        do {
            let journey = try await apiClient.planJourney(from: from, to: to, plan: plan)
            return RouteOption(plan: plan, journey: journey, errorMessage: nil)
        } catch {
            return RouteOption(plan: plan, journey: nil, errorMessage: error.localizedDescription)
        }
    }

    func clearRoute() {
        routeOptions = []
        fromPlace = nil
        toPlace = nil
        searchResults = []
        errorMessage = nil
    }

    /// Populates the map from a journey obtained outside the normal
    /// search flow (e.g. a reloaded saved route), deriving placeholder
    /// from/to markers from the journey's own coordinates since no
    /// searched `Place` exists for it. Shows only that one journey — does
    /// not fetch comparison routes for the other two plans, since reloading
    /// a specific saved route is a distinct flow from fresh planning.
    func loadJourney(_ journey: Journey) {
        routeOptions = [RouteOption(plan: journey.plan, journey: journey, errorMessage: nil)]
        selectedPlan = journey.plan
        searchResults = []
        errorMessage = nil
        let coordinates = journey.allCoordinates
        if let start = coordinates.first {
            fromPlace = Place(id: UUID().uuidString, name: "Start", near: nil,
                               coordinate: Coordinate(longitude: start.longitude, latitude: start.latitude))
        }
        if let end = coordinates.last {
            toPlace = Place(id: UUID().uuidString, name: "End", near: nil,
                             coordinate: Coordinate(longitude: end.longitude, latitude: end.latitude))
        }
    }

    /// Assigns a place to the given waypoint and, once both from and to
    /// are set, plans the route — matching the behavior of picking a
    /// place from search results.
    func selectPlace(_ place: Place, as role: WaypointRole) async {
        switch role {
        case .from: fromPlace = place
        case .to: toPlace = place
        }
        if let from = fromPlace, let to = toPlace {
            await planRoute(from: from.clCoordinate, to: to.clCoordinate)
        }
    }

    /// Fetches the device's current location and assigns it to the given
    /// waypoint as a `Place` named literally "Current Location" — no
    /// reverse geocoding. Reuses `selectPlace(_:as:)` so planning, markers,
    /// and itinerary all behave exactly as they do for a searched place.
    /// On permission denial/restriction, sets
    /// `isPresentingLocationPermissionAlert` instead of `errorMessage` so
    /// `MapView` can offer a direct link to Settings.
    ///
    /// Returns the resolved `Place`, or `nil` if the fetch failed for any
    /// reason. Callers need this to distinguish success from failure without
    /// re-reading `fromPlace`/`toPlace` after the `await` (which can't tell a
    /// fresh assignment apart from a value that was already there).
    @discardableResult
    func useCurrentLocation(as role: WaypointRole) async -> Place? {
        isLoading = true
        do {
            let coordinate = try await locationService.currentLocation()
            isLoading = false
            let place = Place(
                id: UUID().uuidString, name: Place.currentLocationName, near: nil,
                coordinate: Coordinate(longitude: coordinate.longitude, latitude: coordinate.latitude)
            )
            await selectPlace(place, as: role)
            return place
        } catch LocationServiceError.alreadyInProgress {
            // An earlier call is still in flight and still owns `isLoading`;
            // deliberately leave it set and stay silent rather than surfacing
            // an error for what is just a duplicate trigger.
            return nil
        } catch LocationServiceError.permissionDenied, LocationServiceError.restricted {
            isLoading = false
            isPresentingLocationPermissionAlert = true
            return nil
        } catch {
            isLoading = false
            errorMessage = "Couldn't get your current location. Please try again."
            return nil
        }
    }

    /// Fetches the device's current location purely to recenter the map
    /// camera. Unlike `useCurrentLocation(as:)`, this never touches
    /// `fromPlace`/`toPlace` or triggers route planning. The caller doesn't
    /// need the coordinate itself: on success it switches the map camera
    /// into the frameworks' own follow-user-location tracking mode rather
    /// than centering on a point held here. Error handling is
    /// `confirmCurrentLocationAvailable()`'s.
    @discardableResult
    func centerOnCurrentLocation() async -> Bool {
        await confirmCurrentLocationAvailable()
    }

    /// Gate before presenting turn-by-turn navigation. Ferrostar's own location
    /// provider assumes permission is already granted, so this confirms a real fix
    /// through the app's service first. That way a denial surfaces through the same
    /// "Location Access Needed" alert as everywhere else, instead of navigation
    /// silently showing no position. Error handling is
    /// `confirmCurrentLocationAvailable()`'s.
    func prepareNavigation() async -> Bool {
        await confirmCurrentLocationAvailable()
    }

    /// One-shot location fetch used only to confirm access, with the Map screen's
    /// shared error handling: `.permissionDenied`/`.restricted` set
    /// `isPresentingLocationPermissionAlert`, other failures set `errorMessage`,
    /// and `.alreadyInProgress` is swallowed silently, leaving `isLoading` owned
    /// by the first call.
    private func confirmCurrentLocationAvailable() async -> Bool {
        isLoading = true
        do {
            _ = try await locationService.currentLocation()
            isLoading = false
            return true
        } catch LocationServiceError.alreadyInProgress {
            return false
        } catch LocationServiceError.permissionDenied, LocationServiceError.restricted {
            isLoading = false
            isPresentingLocationPermissionAlert = true
            return false
        } catch {
            isLoading = false
            errorMessage = "Couldn't get your current location. Please try again."
            return false
        }
    }
}
