//
//  MockLocationSearchProvider.swift
//  CycleStreets Ride PlannerTests
//

import CoreLocation
@testable import Wheel_Routes

final class MockLocationSearchProvider: LocationSearchProviding {
    struct QueryCall {
        let query: String
        let near: CLLocationCoordinate2D?
    }

    private(set) var queriesReceived: [QueryCall] = []
    var resultsToReturn: [Place] = []
    var errorToThrow: Error?
    /// Queries whose request never completes on its own: it stays in flight until the
    /// calling task is cancelled, then throws `CancellationError`.
    var queriesHeldUntilCancelled: Set<String> = []
    /// Called as each request starts, before any hold.
    var onSearchStarted: ((String) -> Void)?

    func search(query: String, near coordinate: CLLocationCoordinate2D?) async throws -> [Place] {
        try Task.checkCancellation()
        onSearchStarted?(query)
        if queriesHeldUntilCancelled.contains(query) {
            try await Task.sleep(for: .seconds(3600))
        }
        try Task.checkCancellation()
        if let errorToThrow { throw errorToThrow }
        queriesReceived.append(QueryCall(query: query, near: coordinate))
        return resultsToReturn
    }
}
