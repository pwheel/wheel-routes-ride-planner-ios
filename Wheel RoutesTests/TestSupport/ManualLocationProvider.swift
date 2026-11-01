//
//  ManualLocationProvider.swift
//  Wheel RoutesTests
//

import CoreLocation
import FerrostarCore
import FerrostarCoreFFI

/// A `LocationProviding` that reports only the fixes a test sends, synchronously, while
/// updating. `SimulatedLocationProvider` can't step a route deterministically:
/// `NavigationViewModel.start()` loads the route into it, and it then replays that route at
/// 1 Hz on a background task, interleaving with any fixes a test sends. Nothing else moves the
/// rider here, so a test can walk the real Ferrostar core through a route fix by fix.
nonisolated final class ManualLocationProvider: LocationProviding {
    /// Weak because `FerrostarCore` (the delegate) already owns this provider.
    weak var delegate: LocationManagingDelegate?
    let authorizationStatus: CLAuthorizationStatus = .authorizedAlways
    private(set) var lastLocation: UserLocation?
    let lastHeading: Heading? = nil
    private var isUpdating = false

    init(location: UserLocation) {
        lastLocation = location
    }

    func startUpdating() { isUpdating = true }
    func stopUpdating() { isUpdating = false }

    func send(_ location: UserLocation) {
        lastLocation = location
        if isUpdating {
            delegate?.locationManager(self, didUpdateLocations: [location])
        }
    }
}
