//
//  SharedInFlightTaskTests.swift
//  Wheel RoutesTests
//

import Testing
@testable import Wheel_Routes

/// A hand-released stand-in for a slow `CLLocationManager.requestLocation()`:
/// each `run` suspends until the test calls `succeed`/`fail`.
@MainActor
private final class GatedOperation {
    private(set) var startCount = 0
    private var continuation: CheckedContinuation<Int, Error>?

    var isWaiting: Bool { continuation != nil }

    func run() async throws -> Int {
        startCount += 1
        return try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func succeed(_ value: Int) {
        continuation?.resume(returning: value)
        continuation = nil
    }

    func fail(_ error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private struct TestError: Error, Equatable {}

@MainActor
struct SharedInFlightTaskTests {
    /// GitHub #32: the Map screen's background search-bias fetch and a
    /// "Current Location" tap overlap. The second caller must get the same
    /// result as the first, not be rejected and left hanging.
    @Test func concurrentCallersShareOneOperationAndItsResult() async throws {
        let shared = SharedInFlightTask<Int>()
        let operation = GatedOperation()

        let first = Task { try await shared.run { try await operation.run() } }
        try await waitUntil { operation.isWaiting }
        let second = Task { try await shared.run { try await operation.run() } }
        await Task.yield()

        operation.succeed(42)

        #expect(try await first.value == 42)
        #expect(try await second.value == 42)
        #expect(operation.startCount == 1)
    }

    @Test func concurrentCallersAllReceiveTheError() async throws {
        let shared = SharedInFlightTask<Int>()
        let operation = GatedOperation()

        let first = Task { try await shared.run { try await operation.run() } }
        try await waitUntil { operation.isWaiting }
        let second = Task { try await shared.run { try await operation.run() } }
        await Task.yield()

        operation.fail(TestError())

        await #expect(throws: TestError.self) { try await first.value }
        await #expect(throws: TestError.self) { try await second.value }
        #expect(operation.startCount == 1)
    }

    /// Once a fetch has finished, the next call must start a fresh one rather
    /// than replaying a stale coordinate.
    @Test func aCallAfterCompletionStartsANewOperation() async throws {
        let shared = SharedInFlightTask<Int>()
        let operation = GatedOperation()

        let first = Task { try await shared.run { try await operation.run() } }
        try await waitUntil { operation.isWaiting }
        operation.succeed(1)
        #expect(try await first.value == 1)

        let second = Task { try await shared.run { try await operation.run() } }
        try await waitUntil { operation.isWaiting }
        operation.succeed(2)
        #expect(try await second.value == 2)
        #expect(operation.startCount == 2)
    }
}
