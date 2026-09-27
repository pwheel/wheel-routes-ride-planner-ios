//
//  NavigationViewModelTests.swift
//  Wheel RoutesTests
//

import Foundation
import Testing
import FerrostarCore
import FerrostarCoreFFI
@testable import Wheel_Routes

@MainActor
final class NavigationViewModelTests {
    let client = MockAPIClient()
    let locationProvider = SimulatedLocationProvider()
    var idleTimerCalls: [Bool] = []

    /// Muted by default so test runs don't speak cues aloud in the simulator.
    private func makeViewModel(journey: Journey = NavigationFixtures.threeSegmentJourney(), muted: Bool = true) -> NavigationViewModel {
        NavigationViewModel(
            journey: journey, apiClient: client, useMetric: true, isInitiallyMuted: muted,
            locationProvider: locationProvider,
            setIdleTimerDisabled: { [weak self] in self?.idleTimerCalls.append($0) }
        )
    }

    /// A fix ~100 km from the fixture route with good accuracy, so Ferrostar flags a deviation.
    private let farOffRoute = UserLocation(
        coordinates: GeographicCoordinate(lat: 51.5, lng: -0.9),
        horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
    )

    @Test func startBeginsNavigationAndKeepsTheScreenAwake() async throws {
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        #expect(idleTimerCalls == [true])
        #expect(vm.startErrorMessage == nil)
        vm.stop()
    }

    @Test func startIsIdempotent() async throws {
        let vm = makeViewModel()
        vm.start()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        #expect(idleTimerCalls == [true])
        vm.stop()
    }

    @Test func stopEndsNavigationRestoresTheIdleTimerAndIsSafeToRepeat() async throws {
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        vm.stop()
        vm.stop()
        try await waitUntil { vm.navigationState == nil }
        #expect(idleTimerCalls == [true, false])
    }

    @Test func unnavigableJourneyReportsAnErrorWithoutStarting() {
        let vm = makeViewModel(journey: Journey(number: 1, plan: .balanced, lengthMetres: 0, timeSeconds: 0, segments: []))
        vm.start()
        #expect(vm.startErrorMessage == NavigationViewModel.unnavigableRouteMessage)
        #expect(vm.navigationState == nil)
        #expect(idleTimerCalls.isEmpty)
    }

    @Test func failedRerouteShowsABannerAndKeepsNavigating() async throws {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        locationProvider.lastLocation = farOffRoute
        try await waitUntil { vm.rerouteErrorMessage != nil }
        #expect(vm.rerouteErrorMessage == NavigationViewModel.rerouteFailedMessage)
        #expect(vm.navigationState != nil)
        vm.dismissRerouteError()
        #expect(vm.rerouteErrorMessage == nil)
        vm.stop()
    }

    @Test func successfulRerouteSwitchesToTheReplannedRoute() async throws {
        let replanned = client.makeJourney()   // single segment starting at (52.2054, 0.1132)
        client.journeyToReturn = replanned
        let vm = makeViewModel()
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        locationProvider.lastLocation = farOffRoute
        try await waitUntil { vm.navigationState?.routeGeometry.first == GeographicCoordinate(lat: 52.2054, lng: 0.1132) }
        #expect(client.planJourneyCalls.first?.plan == .quietest)
        #expect(vm.rerouteErrorMessage == nil)
        vm.stop()
    }

    @Test func muteStateStartsFromThePersistedValueAndFollowsToggles() async throws {
        let vm = makeViewModel(muted: false)
        #expect(!vm.isMuted)
        vm.toggleMute()
        try await waitUntil { vm.isMuted }
        #expect(makeViewModel(muted: true).isMuted)
    }

    @Test func onlyACompleteTripCountsAsArrived() {
        let summary = TripSummary(distanceTraveled: 820, snappedDistanceTraveled: 820, startedAt: Date(), endedAt: Date())
        #expect(!NavigationViewModel.isComplete(nil))
        #expect(!NavigationViewModel.isComplete(.idle(userLocation: nil)))
        #expect(NavigationViewModel.isComplete(.complete(userLocation: farOffRoute, summary: summary)))
    }
}
