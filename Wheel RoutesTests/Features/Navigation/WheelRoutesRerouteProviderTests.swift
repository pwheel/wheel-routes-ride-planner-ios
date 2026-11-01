//
//  WheelRoutesRerouteProviderTests.swift
//  Wheel RoutesTests
//

import CoreLocation
import Foundation
import Testing
import FerrostarCore
import FerrostarCoreFFI
@testable import Wheel_Routes

@MainActor
struct WheelRoutesRerouteProviderTests {
    private let client = MockAPIClient()
    private let rider = UserLocation(
        coordinates: GeographicCoordinate(lat: 52.2100, lng: 0.1300),
        horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
    )
    private let waypoints = [
        Waypoint(coordinate: GeographicCoordinate(lat: 52.20, lng: 0.10), kind: .break, properties: nil),
        Waypoint(coordinate: GeographicCoordinate(lat: 52.30, lng: 0.20), kind: .break, properties: nil),
    ]

    /// Collects errors passed to `onFailure`.
    private final class FailureLog { var errors: [Error] = [] }

    @Test func replansFromTheRiderToTheFinalWaypointWithTheSamePlan() async throws {
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        _ = try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        let call = try #require(client.planJourneyCalls.only)
        #expect(call.from.latitude == 52.2100 && call.from.longitude == 0.1300)
        #expect(call.to.latitude == 52.30 && call.to.longitude == 0.20)
        #expect(call.plan == .quietest)
    }

    @Test func returnsTheReplannedJourneyAsASingleRoute() async throws {
        client.journeyToReturn = NavigationFixtures.threeSegmentJourney()
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let routes = try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        #expect(routes.count == 1)
        #expect(routes.first?.distance == 820)
    }

    @Test func reportsAndRethrowsPlanningFailures() async {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let log = FailureLog()
        provider.onFailure = { log.errors.append($0) }
        await #expect(throws: URLError.self) {
            try await provider.getRoutes(userLocation: rider, waypoints: waypoints)
        }
        #expect((log.errors.only as? URLError)?.code == .notConnectedToInternet)
    }

    @Test func reportsAndThrowsWhenThereIsNoDestination() async {
        let provider = WheelRoutesRerouteProvider(apiClient: client, plan: .quietest, useMetric: true)
        let log = FailureLog()
        provider.onFailure = { log.errors.append($0) }
        await #expect(throws: WheelRoutesRerouteError.noDestination) {
            try await provider.getRoutes(userLocation: rider, waypoints: [])
        }
        #expect(log.errors.count == 1)
        #expect(client.planJourneyCalls.isEmpty)
    }
}

private extension Array {
    /// The sole element, or nil if the array doesn't have exactly one.
    var only: Element? { count == 1 ? first : nil }
}
