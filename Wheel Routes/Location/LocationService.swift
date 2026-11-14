//
//  LocationService.swift
//  Wheel Routes
//

import CoreLocation

/// Isolated to the main actor so the continuation state below can only ever
/// be touched from one place: `CLLocationManager` delivers its delegate
/// callbacks on the run loop the manager was created on (main, here), and
/// the `async` entry point is main-actor-isolated too, so there is no
/// cross-thread access to synchronize.
@MainActor
protocol LocationServiceProtocol: Sendable {
    /// Fetches a single one-shot fix for the device's current location,
    /// requesting "when in use" authorization first if not yet determined.
    /// A call made while another is still in flight joins it and gets the
    /// same coordinate or error, rather than starting a second request.
    func currentLocation() async throws -> CLLocationCoordinate2D

    /// Non-prompting read of whether location access is already granted
    /// (`.authorizedWhenInUse` or `.authorizedAlways`). Never triggers the
    /// system permission prompt — used to gate features that must not
    /// surprise the user with a prompt outside an explicit user action.
    var isAuthorized: Bool { get }
}

enum LocationServiceError: Error, Equatable {
    case permissionDenied
    case restricted
    case unavailable
}

/// Wraps `CLLocationManager`'s delegate API behind `async/await`. Does a
/// single one-shot `requestLocation()` — no continuous tracking, since
/// route planning only needs one fix. If authorization is
/// `.notDetermined`, requests it in-context (the system prompt fires the
/// first time the user actually taps "Current Location," not at launch).
@MainActor
final class LocationService: NSObject, LocationServiceProtocol, CLLocationManagerDelegate {
    /// Ceiling on how long `requestAuthorization()` waits for a *determined*
    /// status before giving up. Needed because there is a real state —
    /// Location Services switched off device-wide while the app's own status
    /// is still `.notDetermined` — in which `requestWhenInUseAuthorization()`
    /// shows the system "Turn On Location Services?" prompt but never
    /// transitions the app's authorization status, so the only callback we
    /// would ever see is a `.notDetermined` one (which we deliberately
    /// ignore, since the system also emits those spuriously). Without this
    /// ceiling the continuation would never resume and the caller would hang.
    ///
    /// Deliberately generous (not a few seconds): this races the real
    /// system "Allow While Using App?" dialog, which a human has to read
    /// and decide on. A short ceiling here previously caused a false
    /// "couldn't get your current location" error on the very first grant
    /// of the entire feature, because the timeout routinely fired before a
    /// real person finished responding to the prompt (UAT finding, see
    /// docs/superpowers/plans/2026-08-02-uat-findings-current-location.md).
    /// The genuine hang this guards against is rare, and the full-screen
    /// spinner already showing means a long wait here costs little in that
    /// rare case — so bias heavily toward tolerating a slow human over
    /// firing early.
    private static let authorizationTimeout: Duration = .seconds(60)

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var authTimeoutTask: Task<Void, Never>?
    /// Coalesces overlapping `currentLocation()` calls into one fetch, so the
    /// single `locationContinuation`/`authContinuation` slots are never
    /// overwritten (which would leak a continuation and hang its caller).
    private let sharedFetch = SharedInFlightTask<CLLocationCoordinate2D>()

    override init() {
        super.init()
        manager.delegate = self
    }

    /// Non-prompting read of `CLLocationManager`'s current authorization
    /// status — never triggers the system permission prompt.
    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    func currentLocation() async throws -> CLLocationCoordinate2D {
        try await sharedFetch.run { [unowned self] in try await self.fetchCurrentLocation() }
    }

    private func fetchCurrentLocation() async throws -> CLLocationCoordinate2D {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization()
        }
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied:
            throw LocationServiceError.permissionDenied
        case .restricted:
            throw LocationServiceError.restricted
        case .notDetermined:
            // Either the authorization wait timed out, or the user dismissed
            // the prompt without deciding. Nothing to link to in Settings —
            // this is a "try again" condition, not a denial.
            throw LocationServiceError.unavailable
        @unknown default:
            // A status this build doesn't know about is more likely a
            // transient/unsupported condition than an outright denial, so
            // prefer the generic "try again" path over sending the user to
            // Settings on a guess. Matches the `.notDetermined` fallback.
            throw LocationServiceError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.locationContinuation = continuation
            manager.requestLocation()
        }
    }

    private func requestAuthorization() async -> CLAuthorizationStatus {
        await withCheckedContinuation { continuation in
            self.authContinuation = continuation
            self.authTimeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.authorizationTimeout)
                guard !Task.isCancelled else { return }
                // Resume with the still-undetermined status; `currentLocation()`
                // maps it to `.unavailable`.
                self?.resumeAuthorization(with: .notDetermined)
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Resumes a pending authorization wait exactly once, cancelling the
    /// timeout that races it.
    private func resumeAuthorization(with status: CLAuthorizationStatus) {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        continuation.resume(returning: status)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // `CLLocationManager` delivers delegate callbacks on the run loop it
        // was created on — main, because this class is `@MainActor` — so the
        // assumption below is sound, and it lets a main-actor-isolated type
        // satisfy this non-isolated protocol requirement without hopping
        // (which would reorder callbacks relative to the continuation state).
        MainActor.assumeIsolated {
            let status = manager.authorizationStatus
            // The system emits `.notDetermined` callbacks spuriously (e.g. on
            // delegate assignment), so only a determined status resolves the
            // wait. `authorizationTimeout` is what stops that guard from
            // hanging forever when `.notDetermined` is genuinely all we'll get.
            guard status != .notDetermined else { return }
            resumeAuthorization(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        MainActor.assumeIsolated {
            guard let location = locations.last else { return }
            locationContinuation?.resume(returning: location.coordinate)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated {
            // `CLError.denied` means Location Services are off system-wide even
            // though the app's own status is authorized — that's fixable in
            // Settings, so route it to the Settings-linking alert rather than
            // the generic "try again" one.
            let mapped: LocationServiceError =
                (error as? CLError)?.code == .denied ? .permissionDenied : .unavailable
            locationContinuation?.resume(throwing: mapped)
            locationContinuation = nil
        }
    }
}
