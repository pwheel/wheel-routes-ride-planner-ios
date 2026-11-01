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
    private func makeViewModel(
        journey: Journey = NavigationFixtures.threeSegmentJourney(), muted: Bool = true,
        locationProvider: LocationProviding? = nil
    ) -> NavigationViewModel {
        NavigationViewModel(
            journey: journey, apiClient: client, useMetric: true, isInitiallyMuted: muted,
            locationProvider: locationProvider ?? self.locationProvider,
            setIdleTimerDisabled: { [weak self] in self?.idleTimerCalls.append($0) },
            speechSynthesizer: SilentSpeechSynthesizer()
        )
    }

    /// A fix ~100 km from the fixture route with good accuracy, so Ferrostar flags a deviation.
    private let farOffRoute = UserLocation(
        coordinates: GeographicCoordinate(lat: 51.5, lng: -0.9),
        horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
    )

    /// A good-accuracy fix at the given point.
    private func fix(lat: Double, lng: Double) -> UserLocation {
        UserLocation(
            coordinates: GeographicCoordinate(lat: lat, lng: lng),
            horizontalAccuracy: 5, courseOverGround: nil, timestamp: Date(), speed: nil
        )
    }

    /// The raw (unsnapped) fix in the view model's latest published trip state.
    private func reportedCoordinate(_ vm: NavigationViewModel) -> GeographicCoordinate? {
        switch vm.navigationState?.tripState {
        case let .navigating(_, userLocation, _, _, _, _, _, _, _, _, _): userLocation.coordinates
        case let .complete(userLocation, _): userLocation.coordinates
        default: nil
        }
    }

    /// Sends a fix and waits until the view model has received the state the core built from
    /// it. Ferrostar evaluates each fix against its last state but publishes states
    /// asynchronously on the main queue, so sending the next fix any earlier would evaluate it
    /// against a stale state.
    private func send(_ location: UserLocation, via provider: ManualLocationProvider, to vm: NavigationViewModel) async throws {
        provider.send(location)
        try await waitUntil { reportedCoordinate(vm) == location.coordinates }
    }

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

    @Test func rejoiningTheRouteClearsAFailedRerouteBanner() async throws {
        client.shouldThrow = URLError(.notConnectedToInternet)
        let provider = ManualLocationProvider(location: fix(lat: 52.20, lng: 0.10))
        let vm = makeViewModel(locationProvider: provider)
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        // Ferrostar judges deviation from the previous fix, so the second off-route fix is the
        // one that triggers the (failing) reroute.
        try await send(fix(lat: 51.5, lng: -0.9), via: provider, to: vm)
        try await send(fix(lat: 51.5, lng: -0.91), via: provider, to: vm)
        // `isCalculatingNewRoute` returning to false means the core has also started its
        // recalculation cooldown, so the next fix can't trigger another (failing) reroute.
        try await waitUntil { vm.rerouteErrorMessage != nil && vm.navigationState?.isCalculatingNewRoute == false }
        #expect(vm.rerouteErrorMessage == NavigationViewModel.rerouteFailedMessage)

        // Back on High Street. The first fix is still judged against the off-route one; the
        // second reports no deviation.
        try await send(fix(lat: 52.20, lng: 0.10), via: provider, to: vm)
        try await send(fix(lat: 52.205, lng: 0.105), via: provider, to: vm)
        #expect(vm.navigationState?.currentDeviation == .noDeviation)
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

    @Test func arrivalEndsTheSessionButKeepsTheArrivalCard() async throws {
        let provider = ManualLocationProvider(location: fix(lat: 52.20, lng: 0.10))
        let vm = makeViewModel(locationProvider: provider)
        vm.start()
        try await waitUntil { vm.navigationState != nil }
        // End of High Street (step 0): Ferrostar notes the rider has reached the step's end…
        try await send(fix(lat: 52.21, lng: 0.11), via: provider, to: vm)
        // …and advances once they've left it. Here that's the end of Mill Road, so the arrival
        // condition (within 15 m of the step's end) advances again, onto the final short link.
        try await send(fix(lat: 52.20, lng: 0.12), via: provider, to: vm)
        // The destination completes the trip.
        provider.send(fix(lat: 52.201, lng: 0.121))
        try await waitUntil { vm.hasArrived }
        #expect(idleTimerCalls == [true, false])

        // Ending the session clears the core's state, but the arrival card must survive it.
        try await waitUntil { vm.navigationState == nil }
        #expect(vm.hasArrived)

        // Done/Exit afterwards doesn't touch the idle timer again.
        vm.stop()
        #expect(idleTimerCalls == [true, false])
    }

    @Test func onlyACompleteTripCountsAsArrived() {
        let summary = TripSummary(distanceTraveled: 820, snappedDistanceTraveled: 820, startedAt: Date(), endedAt: Date())
        #expect(!NavigationViewModel.isComplete(nil))
        #expect(!NavigationViewModel.isComplete(.idle(userLocation: nil)))
        #expect(NavigationViewModel.isComplete(.complete(userLocation: farOffRoute, summary: summary)))
    }
}
