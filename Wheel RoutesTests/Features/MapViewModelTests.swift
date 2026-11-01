//
//  MapViewModelTests.swift
//  Wheel RoutesTests
//

import Testing
import Foundation
import CoreLocation
@testable import Wheel_Routes

@MainActor
final class MapViewModelTests {
    let client: MockAPIClient
    let locationService: MockLocationService
    let searchProvider: MockLocationSearchProvider
    let vm: MapViewModel

    init() {
        client = MockAPIClient()
        locationService = MockLocationService()
        searchProvider = MockLocationSearchProvider()
        vm = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
    }

    @Test func testSearchUpdatesPlaces() async throws {
        searchProvider.resultsToReturn = [
            Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
                  coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        ]
        await vm.search(query: "Cambridge")
        #expect(vm.searchResults.count == 1)
        #expect(vm.searchResults[0].name == "Cambridge")
    }

    @Test func testPlanRoutePopulatesJourney() async throws {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.currentJourney != nil)
        #expect(vm.currentJourney?.number == journey.number)
    }

    @Test func testPlanRouteAllPlansFailLeavesCurrentJourneyNil() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.currentJourney == nil)
        #expect(vm.routeOptions.count == 3)
        #expect(vm.routeOptions.allSatisfy { $0.journey == nil && $0.errorMessage != nil })
        #expect(vm.errorMessage == nil)
    }

    @Test func testClearRouteResetsState() async {
        client.journeyToReturn = client.makeJourney()
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.clearRoute()
        #expect(vm.currentJourney == nil)
        #expect(vm.routeOptions.isEmpty)
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
    }

    @Test func testLoadJourneySetsCurrentJourney() {
        let journey = client.makeJourney()
        vm.loadJourney(journey)
        #expect(vm.currentJourney == journey)
    }

    @Test func testLoadJourneyDerivesFromAndToPlacesFromCoordinates() {
        let journey = client.makeJourney()
        let first = journey.allCoordinates.first!
        let last = journey.allCoordinates.last!
        vm.loadJourney(journey)
        #expect(vm.fromPlace?.coordinate.longitude == first.longitude)
        #expect(vm.fromPlace?.coordinate.latitude == first.latitude)
        #expect(vm.toPlace?.coordinate.longitude == last.longitude)
        #expect(vm.toPlace?.coordinate.latitude == last.latitude)
    }

    @Test func testLoadJourneyClearsSearchResultsAndError() {
        vm.searchResults = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.errorMessage = "stale error"
        vm.loadJourney(client.makeJourney())
        #expect(vm.searchResults.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func testSelectPlaceAsFromOnlySetsFromPlace() async {
        let place = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        await vm.selectPlace(place, as: .from)
        #expect(vm.fromPlace == place)
        #expect(vm.toPlace == nil)
        #expect(vm.currentJourney == nil)
    }

    @Test func testSelectPlaceAsToAfterFromTriggersPlanRoute() async {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        let to = Place(id: "2", name: "Work", near: nil, coordinate: Coordinate(longitude: 0.2, latitude: 52.1))
        await vm.selectPlace(from, as: .from)
        await vm.selectPlace(to, as: .to)
        #expect(vm.toPlace == to)
        #expect(vm.currentJourney?.number == journey.number)
    }

    @Test func testUseCurrentLocationAsFromSetsPlaceNamedCurrentLocation() async {
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let returned = await vm.useCurrentLocation(as: .from)
        #expect(returned?.name == "Current Location")
        #expect(returned == vm.fromPlace)
        #expect(vm.fromPlace?.name == "Current Location")
        #expect(vm.fromPlace?.coordinate.latitude == 51.5)
        #expect(vm.fromPlace?.coordinate.longitude == -0.1)
        // Only .from is set (no .to yet), so planRoute never runs — isLoading
        // must still end up false, not get stuck true waiting for a
        // planRoute that was never going to happen.
        #expect(!vm.isLoading)
        // The "Current Location" Place must never leak into searchResults:
        // the dropdown's bookmark affordance is driven off that array, and
        // saving a coordinate under the name "Current Location" would go
        // stale the moment the user moves.
        #expect(vm.searchResults.isEmpty)
    }

    @Test func testUseCurrentLocationAsToAfterFromTriggersPlanRoute() async {
        let journey = client.makeJourney()
        client.journeyToReturn = journey
        let from = Place(id: "1", name: "Home", near: nil, coordinate: Coordinate(longitude: 0.1, latitude: 52.0))
        await vm.selectPlace(from, as: .from)
        let returned = await vm.useCurrentLocation(as: .to)
        #expect(returned?.name == "Current Location")
        #expect(returned == vm.toPlace)
        #expect(vm.toPlace?.name == "Current Location")
        #expect(vm.currentJourney?.number == journey.number)
        #expect(vm.searchResults.isEmpty)
    }

    @Test func testUseCurrentLocationPermissionDeniedPresentsAlertAndDoesNotSetPlace() async {
        locationService.errorToThrow = LocationServiceError.permissionDenied
        let returned = await vm.useCurrentLocation(as: .from)
        #expect(returned == nil)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
    }

    @Test func testUseCurrentLocationRestrictedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.restricted
        let returned = await vm.useCurrentLocation(as: .from)
        #expect(returned == nil)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
        #expect(!vm.isLoading)
    }

    @Test func testUseCurrentLocationUnavailableSetsErrorMessage() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        let returned = await vm.useCurrentLocation(as: .from)
        #expect(returned == nil)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
        #expect(!vm.isLoading)
    }

    /// A duplicate trigger while a fetch is in flight is rejected by
    /// `LocationService` rather than being allowed to strand the first call's
    /// continuation. The ViewModel must swallow that rejection silently — no
    /// error alert, and `isLoading` left alone because the still-running first
    /// call owns it.
    @Test func testUseCurrentLocationAlreadyInProgressIsSilentAndLeavesLoadingAlone() async {
        locationService.errorToThrow = LocationServiceError.alreadyInProgress
        let returned = await vm.useCurrentLocation(as: .from)
        #expect(returned == nil)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(vm.fromPlace == nil)
        #expect(vm.isLoading)
    }

    @Test func testIsLocationAuthorizedReflectsLocationService() {
        locationService.isAuthorized = false
        #expect(!vm.isLocationAuthorized)
        locationService.isAuthorized = true
        #expect(vm.isLocationAuthorized)
    }

    @Test func testCenterOnCurrentLocationSucceedsWithoutTouchingWaypointsOrRoute() async {
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(succeeded)
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
        #expect(vm.routeOptions.isEmpty)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationPermissionDeniedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.permissionDenied
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationRestrictedPresentsAlert() async {
        locationService.errorToThrow = LocationServiceError.restricted
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.isPresentingLocationPermissionAlert)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationUnavailableSetsErrorMessage() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.errorMessage != nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(!vm.isLoading)
    }

    @Test func testCenterOnCurrentLocationAlreadyInProgressIsSilentAndLeavesLoadingAlone() async {
        locationService.errorToThrow = LocationServiceError.alreadyInProgress
        let succeeded = await vm.centerOnCurrentLocation()
        #expect(!succeeded)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
        #expect(vm.isLoading)
    }

    @Test func testSearchTextChangedWithEmptyQueryClearsResultsImmediately() {
        vm.searchResults = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.searchTextChanged("")
        #expect(vm.searchResults.isEmpty)
    }

    @Test func testSearchTextChangedDebouncesAndSearches() async throws {
        vm.searchDebounceMilliseconds = 100
        searchProvider.resultsToReturn = [
            Place(id: "1", name: "Cambridge", near: "Cambridgeshire",
                  coordinate: Coordinate(longitude: 0.1218, latitude: 52.2053))
        ]
        vm.searchTextChanged("Cambridge")
        try await waitUntil { vm.searchResults.count == 1 }
        #expect(vm.searchResults.count == 1)
        #expect(searchProvider.queriesReceived.map(\.query) == ["Cambridge"])
    }

    @Test func testSearchTextChangedCancelsPendingSearchOnRapidTyping() async throws {
        vm.searchDebounceMilliseconds = 150
        searchProvider.resultsToReturn = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.searchTextChanged("Ca")
        try await Task.sleep(for: .milliseconds(50))
        vm.searchTextChanged("Cambridge")
        try await waitUntil { searchProvider.queriesReceived.map(\.query) == ["Cambridge"] }
        #expect(searchProvider.queriesReceived.map(\.query) == ["Cambridge"])
    }

    @Test func testSearchTextChangedDoesNotSetErrorMessageWhenDebounceFires() async throws {
        vm.searchDebounceMilliseconds = 10
        searchProvider.resultsToReturn = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.searchTextChanged("Cambridge")
        try await waitUntil { vm.searchResults.count == 1 }
        #expect(vm.errorMessage == nil)
        #expect(vm.searchResults.count == 1)
    }

    @Test func testSearchTextChangedDoesNotSetErrorMessageWhenInFlightSearchIsSuperseded() async throws {
        vm.searchDebounceMilliseconds = 10
        searchProvider.delayMilliseconds = 100
        searchProvider.resultsToReturn = [
            Place(id: "1", name: "Cambridge", near: nil, coordinate: Coordinate(longitude: 0, latitude: 0))
        ]
        vm.searchTextChanged("Ca")
        try await Task.sleep(for: .milliseconds(30))
        vm.searchTextChanged("Cambridge")
        try await waitUntil { vm.searchResults.count == 1 }
        #expect(vm.errorMessage == nil)
        #expect(vm.searchResults.count == 1)
    }

    @Test func testInitSetsSelectedPlanFromInitialValue() {
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider, initialSelectedPlan: .fastest)
        #expect(vm2.selectedPlan == .fastest)
    }

    @Test func testPlanRouteAllPlansSucceedPopulatesRouteOptions() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .balanced: client.makeJourney(plan: .balanced),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        let from = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        let to   = CLLocationCoordinate2D(latitude: 52.1952, longitude: 0.1201)
        await vm.planRoute(from: from, to: to)
        #expect(vm.routeOptions.count == 3)
        #expect(vm.routeOptions.allSatisfy { $0.journey != nil })
        #expect(vm.currentJourney?.plan == .balanced)
    }

    @Test func testPlanRoutePartialFailureOnSelectedPlanFallsBackToFirstSuccess() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        client.errorsByPlan = [.balanced: NSError(domain: "Test", code: 1)]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        #expect(vm.selectedPlan == .quietest)
        #expect(vm.currentJourney?.plan == .quietest)
    }

    @Test func testPlanRoutePartialFailureOnNonSelectedPlanKeepsSelection() async {
        client.journeysByPlan = [
            .balanced: client.makeJourney(plan: .balanced),
            .quietest: client.makeJourney(plan: .quietest)
        ]
        client.errorsByPlan = [.fastest: NSError(domain: "Test", code: 1)]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        #expect(vm.selectedPlan == .balanced)
        #expect(vm.currentJourney?.plan == .balanced)
        let fastestOption = vm.routeOptions.first { $0.plan == .fastest }
        #expect(fastestOption?.journey == nil)
        #expect(fastestOption?.errorMessage != nil)
    }

    @Test func testSelectingDifferentPlanUpdatesCurrentJourney() async {
        client.journeysByPlan = [
            .quietest: client.makeJourney(plan: .quietest),
            .balanced: client.makeJourney(plan: .balanced),
            .fastest: client.makeJourney(plan: .fastest)
        ]
        let c = CLLocationCoordinate2D(latitude: 52.2054, longitude: 0.1132)
        await vm.planRoute(from: c, to: c)
        vm.selectedPlan = .fastest
        #expect(vm.currentJourney?.plan == .fastest)
    }

    @Test func testLoadJourneySetsSelectedPlanToJourneysPlan() {
        let journey = client.makeJourney(plan: .fastest)
        vm.loadJourney(journey)
        #expect(vm.selectedPlan == .fastest)
        #expect(vm.currentJourney == journey)
    }

    @Test func testBiasCoordinateSetWhenLocationAuthorized() async throws {
        locationService.isAuthorized = true
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        vm2.loadBiasCoordinateIfAuthorized()
        try await waitUntil { vm2.biasCoordinate != nil }
        #expect(vm2.biasCoordinate?.latitude == 51.5)
        #expect(vm2.biasCoordinate?.longitude == -0.1)
    }

    @Test func testBiasCoordinateNotSetWhenLocationUnauthorized() async throws {
        locationService.isAuthorized = false
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        vm2.loadBiasCoordinateIfAuthorized()
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm2.biasCoordinate == nil)
    }

    @Test func testSearchPassesBiasCoordinateToProvider() async throws {
        locationService.isAuthorized = true
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        vm2.loadBiasCoordinateIfAuthorized()
        try await waitUntil { vm2.biasCoordinate != nil }
        await vm2.search(query: "Cambridge")
        #expect(searchProvider.queriesReceived.last?.near?.latitude == 51.5)
        #expect(searchProvider.queriesReceived.last?.near?.longitude == -0.1)
    }

    /// Proves the side effect moved out of `init`: constructing a
    /// `MapViewModel` with an already-authorized location service must not,
    /// on its own, populate `biasCoordinate` — only an explicit
    /// `loadBiasCoordinateIfAuthorized()` call should trigger the fetch.
    /// This guards against the GPS-fetch-on-every-discarded-reconstruction
    /// bug `MapView` previously had via `@State(initialValue:)`.
    @Test func testInitAloneDoesNotPopulateBiasCoordinateEvenWhenAuthorized() async throws {
        locationService.isAuthorized = true
        locationService.coordinateToReturn = CLLocationCoordinate2D(latitude: 51.5, longitude: -0.1)
        let vm2 = MapViewModel(apiClient: client, locationService: locationService, searchProvider: searchProvider)
        // Give any errant background work a chance to run before asserting.
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm2.biasCoordinate == nil)
    }

    @Test func testSearchPassesNilNearWhenNoBiasCoordinate() async throws {
        await vm.search(query: "Cambridge")
        #expect(searchProvider.queriesReceived.last?.near == nil)
    }

    // MARK: - prepareNavigation

    @Test func prepareNavigationSucceedsWhenALocationFixIsAvailable() async {
        let ready = await vm.prepareNavigation()
        #expect(ready)
        #expect(!vm.isLoading)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationOffersSettingsWhenPermissionIsDeniedOrRestricted() async {
        for error in [LocationServiceError.permissionDenied, .restricted] {
            vm.isPresentingLocationPermissionAlert = false
            locationService.errorToThrow = error
            let ready = await vm.prepareNavigation()
            #expect(!ready)
            #expect(vm.isPresentingLocationPermissionAlert)
            #expect(!vm.isLoading)
        }
    }

    @Test func prepareNavigationShowsAGenericErrorWhenLocationIsUnavailable() async {
        locationService.errorToThrow = LocationServiceError.unavailable
        let ready = await vm.prepareNavigation()
        #expect(!ready)
        #expect(vm.errorMessage == "Couldn't get your current location. Please try again.")
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationStaysSilentForADuplicateInFlightFetch() async {
        locationService.errorToThrow = LocationServiceError.alreadyInProgress
        let ready = await vm.prepareNavigation()
        #expect(!ready)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isPresentingLocationPermissionAlert)
    }

    @Test func prepareNavigationNeverTouchesWaypointsOrRoutes() async {
        _ = await vm.prepareNavigation()
        #expect(vm.fromPlace == nil)
        #expect(vm.toPlace == nil)
        #expect(vm.routeOptions.isEmpty)
    }
}
