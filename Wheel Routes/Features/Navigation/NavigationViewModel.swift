//
//  NavigationViewModel.swift
//  Wheel Routes
//

import Combine
import CoreLocation
import FerrostarCore
import FerrostarCoreFFI
import Foundation
import Observation
import UIKit

/// Drives one turn-by-turn session over a `FerrostarCore`: starts it from an
/// already-planned `Journey`, accepts automatic reroutes, surfaces reroute failures
/// (which Ferrostar itself swallows), mirrors the mute state, and keeps the screen
/// awake while active. One instance per session. `MapView` creates it when the
/// rider taps Start.
@Observable
@MainActor
final class NavigationViewModel {
    static let rerouteFailedMessage = "Couldn't recalculate route"
    static let unnavigableRouteMessage = "This route can't be navigated."

    /// Starting values from the design spec, to be tuned during on-device testing.
    /// Fixes less accurate than this are ignored for deviation checks.
    static let deviationMinimumHorizontalAccuracy: UInt16 = 25
    /// How far (in metres) from the route line counts as off-route.
    static let maxAcceptableDeviationMetres: Double = 25

    private(set) var navigationState: NavigationState?
    private(set) var isMuted: Bool
    private(set) var rerouteErrorMessage: String?
    private(set) var startErrorMessage: String?
    /// Latched the first time the trip completes, which also ends the session (see
    /// `handle(_:)`). Ending it clears `navigationState`, so this can't be derived from that.
    private(set) var hasArrived = false

    @ObservationIgnored private let core: FerrostarCore
    @ObservationIgnored private let journey: Journey
    @ObservationIgnored private let useMetric: Bool
    @ObservationIgnored private let locationProvider: LocationProviding
    @ObservationIgnored private let setIdleTimerDisabled: (Bool) -> Void
    /// Held strongly here because `FerrostarCore.delegate` is weak.
    @ObservationIgnored private let coreDelegate = CoreDelegateProxy()
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var isActive = false

    init(
        journey: Journey,
        apiClient: any APIClientProtocol,
        useMetric: Bool,
        isInitiallyMuted: Bool,
        locationProvider: LocationProviding,
        setIdleTimerDisabled: @escaping (Bool) -> Void = { UIApplication.shared.isIdleTimerDisabled = $0 }
    ) {
        let rerouteProvider = WheelRoutesRerouteProvider(apiClient: apiClient, plan: journey.plan, useMetric: useMetric)
        self.journey = journey
        self.useMetric = useMetric
        self.locationProvider = locationProvider
        self.setIdleTimerDisabled = setIdleTimerDisabled
        self.isMuted = isInitiallyMuted
        self.core = FerrostarCore(
            customRouteProvider: rerouteProvider,
            locationProvider: locationProvider,
            navigationControllerConfig: Self.navigationControllerConfig,
            spokenInstructionObserver: .initAVSpeechSynthesizer(isMuted: isInitiallyMuted)
        )

        core.delegate = coreDelegate
        coreDelegate.onRoutesLoaded = { [weak self] routes in self?.acceptReroute(routes) }
        rerouteProvider.onFailure = { [weak self] _ in
            Task { @MainActor in
                // `stop()` cancels any in-flight reroute, which also surfaces as a failure.
                guard let self, self.isActive else { return }
                self.rerouteErrorMessage = Self.rerouteFailedMessage
            }
        }
        core.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)
        core.spokenInstructionObserver.$isMuted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in self?.isMuted = muted }
            .store(in: &cancellables)
    }

    /// Converts the journey and starts the Ferrostar session. Safe to call more than once;
    /// only the first call of an active session does anything.
    func start() {
        guard !isActive else { return }
        do {
            let route = try JourneyRouteAdapter.route(from: journey, useMetric: useMetric)
            if let simulated = locationProvider as? SimulatedLocationProvider {
                try simulated.setSimulatedRoute(route)
            }
            try core.startNavigation(route: route)
            isActive = true
            setIdleTimerDisabled(true)
        } catch {
            startErrorMessage = Self.unnavigableRouteMessage
        }
    }

    /// Ends the session and lets the screen sleep again. Safe to call more than once.
    func stop() {
        guard isActive else { return }
        isActive = false
        core.stopNavigation()
        setIdleTimerDisabled(false)
    }

    func toggleMute() {
        core.spokenInstructionObserver.toggleMute()
    }

    func dismissRerouteError() {
        rerouteErrorMessage = nil
    }

    nonisolated static func isComplete(_ tripState: TripState?) -> Bool {
        guard let tripState, case .complete = tripState else { return false }
        return true
    }

    /// Real GPS for rides. In DEBUG builds, the launch argument `-simulateNavigation` replays
    /// the route instead (`start()` loads it into the simulator), for checking navigation in
    /// the iOS Simulator without a GPX file.
    static func makeLocationProvider() -> LocationProviding {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulateNavigation") {
            return SimulatedLocationProvider()
        }
        #endif
        return CoreLocationProvider(activityType: .fitness, allowBackgroundLocationUpdates: false)
    }

    private func handle(_ state: NavigationState?) {
        navigationState = state
        // A failed-reroute banner is stale once a new recalculation starts (it would otherwise
        // hide "Recalculating route…") or once the rider is back on the route.
        if state?.isCalculatingNewRoute == true || state?.currentDeviation == .noDeviation {
            rerouteErrorMessage = nil
        }
        // Ferrostar's `.complete` doesn't stop GPS or speech, so end the session here rather
        // than waiting for Done, in case the rider pockets the phone at the destination.
        if !hasArrived, Self.isComplete(state?.tripState) {
            hasArrived = true
            stop()
        }
    }

    private func acceptReroute(_ routes: [Route]) {
        guard isActive, let route = routes.first else { return }
        do {
            try core.startNavigation(route: route)
            rerouteErrorMessage = nil
        } catch {
            rerouteErrorMessage = Self.rerouteFailedMessage
        }
    }

    private static var navigationControllerConfig: SwiftNavigationControllerConfig {
        SwiftNavigationControllerConfig(
            waypointAdvance: .waypointWithinRange(50),
            stepAdvanceCondition: stepAdvanceDistanceEntryAndExit(
                distanceToEndOfStep: 20, distanceAfterEndOfStep: 5, minimumHorizontalAccuracy: 25
            ),
            arrivalStepAdvanceCondition: stepAdvanceDistanceToEndOfStep(distance: 15, minimumHorizontalAccuracy: 25),
            routeDeviationTracking: .staticThreshold(
                minimumHorizontalAccuracy: deviationMinimumHorizontalAccuracy,
                maxAcceptableDeviation: maxAcceptableDeviationMetres
            ),
            snappedLocationCourseFiltering: .snapToRoute
        )
    }
}

/// Ferrostar 0.57.0 calls `core(_:loadedAlternateRoutes:)` from an unstructured `Task`,
/// possibly off the main actor, so this nonisolated shim hops to the main actor before
/// forwarding. It always requests a reroute on deviation.
private nonisolated final class CoreDelegateProxy: FerrostarCoreDelegate {
    var onRoutesLoaded: (@MainActor ([Route]) -> Void)?

    func core(_: FerrostarCore, didStartWith _: Route) {}

    func core(
        _: FerrostarCore,
        correctiveActionForDeviation _: DeviationKind,
        remainingWaypoints waypoints: [Waypoint]
    ) -> CorrectiveAction {
        .getNewRoutes(waypoints: waypoints)
    }

    func core(_: FerrostarCore, loadedAlternateRoutes routes: [Route]) {
        let handler = onRoutesLoaded
        Task { @MainActor in handler?(routes) }
    }
}
