//
//  WaitUntil.swift
//  Wheel RoutesTests
//

import Testing

/// Polls `condition` until it becomes true or the polling budget runs out, instead of
/// sleeping a fixed duration and hoping the async work under test finished in time.
/// Suites run with default (non-serialized) Swift Testing parallelism, so a fixed sleep
/// margin is unreliable under CI's variable CPU contention.
///
/// The budget is counted in polls (`timeout / pollInterval`), not as a wall-clock
/// deadline. CI simulator clones have been seen to stall the main actor for longer than
/// 5 s; a deadline expires during such a stall even though neither the poller nor the
/// work it's waiting for could run, while a poll count only advances when the poller
/// actually gets a turn. A condition that never holds still fails after at least
/// `timeout` of real time.
///
/// Prefer awaiting the work directly (e.g. a `Task`'s `value`) when the code under test
/// exposes it; that needs no budget at all.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(5),
    pollInterval: Duration = .milliseconds(10),
    _ condition: () -> Bool
) async throws {
    let maxPolls = Int((timeout / pollInterval).rounded(.up))
    for _ in 0..<maxPolls {
        if condition() { return }
        try await Task.sleep(for: pollInterval)
    }
    if condition() { return }
    Issue.record("Condition still false after \(maxPolls) polls (at least \(timeout))")
}
