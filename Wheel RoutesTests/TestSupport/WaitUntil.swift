//
//  WaitUntil.swift
//  Wheel RoutesTests
//

import Testing

/// Polls `condition` until it becomes true or `timeout` elapses, instead of
/// sleeping a fixed duration and hoping the async work under test finished in
/// time. Suites run with default (non-serialized) Swift Testing parallelism,
/// so a fixed sleep margin is unreliable under CI's variable CPU contention.
/// Condition-based waiting is deterministic regardless of scheduling delay.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(10),
    _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Timed out after \(timeout) waiting for condition")
            return
        }
        try await Task.sleep(for: pollInterval)
    }
}
