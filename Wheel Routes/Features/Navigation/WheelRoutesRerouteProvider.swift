//
//  WheelRoutesRerouteProvider.swift
//  Wheel Routes
//

import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

nonisolated enum WheelRoutesRerouteError: Error, Equatable {
    /// Ferrostar asked for a route with no remaining waypoints to head for.
    case noDestination
}

/// Ferrostar `CustomRouteProvider` used when the rider leaves the route: re-plans from
/// their current position to the final remaining waypoint with the same `RoutePlan`,
/// through the app's existing CycleStreets client.
///
/// `nonisolated` because `FerrostarCore` calls `getRoutes` from an unstructured `Task`,
/// off the main actor.
nonisolated final class WheelRoutesRerouteProvider: CustomRouteProvider {
    private let apiClient: any APIClientProtocol
    private let plan: RoutePlan
    private let useMetric: Bool

    /// Called with the error before it's rethrown. Ferrostar 0.57.0 swallows reroute errors
    /// (`catch {}` in `FerrostarCore`), so this is the only way the UI learns a reroute failed.
    /// May be called off the main actor.
    var onFailure: ((Error) -> Void)?

    init(apiClient: any APIClientProtocol, plan: RoutePlan, useMetric: Bool) {
        self.apiClient = apiClient
        self.plan = plan
        self.useMetric = useMetric
    }

    func getRoutes(userLocation: UserLocation, waypoints: [Waypoint]) async throws -> [Route] {
        do {
            guard let destination = waypoints.last else { throw WheelRoutesRerouteError.noDestination }
            let journey = try await apiClient.planJourney(
                from: CLLocationCoordinate2D(latitude: userLocation.coordinates.lat, longitude: userLocation.coordinates.lng),
                to: CLLocationCoordinate2D(latitude: destination.coordinate.lat, longitude: destination.coordinate.lng),
                plan: plan
            )
            return [try JourneyRouteAdapter.route(from: journey, useMetric: useMetric)]
        } catch {
            onFailure?(error)
            throw error
        }
    }
}
