//
//  SharedInFlightTask.swift
//  Wheel Routes
//

/// Runs at most one instance of an async operation at a time. A caller that
/// arrives while one is already running doesn't start a second; it awaits the
/// running one and gets the same result or error. Once it finishes, the next
/// call starts a fresh run, so nothing is cached between runs.
///
/// `LocationService` uses this so overlapping `currentLocation()` calls (e.g.
/// the Map screen's background search-bias fetch and a "Current Location" tap)
/// share one `CLLocationManager.requestLocation()`. It used to reject the
/// second caller instead, which left the Map screen's spinner stuck on
/// (GitHub #32).
@MainActor
final class SharedInFlightTask<Value: Sendable> {
    private var inFlight: Task<Value, Error>?

    func run(_ operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        if let inFlight { return try await inFlight.value }
        let task = Task { @MainActor in try await operation() }
        inFlight = task
        // Only the caller that started the run clears it. Joiners never create
        // a task, so this can't clear a newer run.
        defer { inFlight = nil }
        return try await task.value
    }
}
