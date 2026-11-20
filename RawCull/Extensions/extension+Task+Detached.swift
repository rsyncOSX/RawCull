//
//  extension+Task+Detached.swift
//  RawCull
//
//  Runs blocking file and image work off the caller's actor while keeping it
//  tied to the caller's cancellation. `Task.detached` does not inherit
//  cancellation, so awaiting its `.value` kept a decode or sharpen running after
//  the request that wanted it (a catalog switch, a cancelled preload) was gone.
//
//  The work runs as a child task in a task group instead. A child task of a
//  cancelled task starts already cancelled, and later cancellation of the caller
//  propagates to it automatically, so there is no window in which the work can
//  start before it learns the caller is cancelled. The work itself should still
//  check `Task.isCancelled` before its expensive step.
//

import Foundation

/// Runs `operation` off the caller's actor as a child task that shares the
/// caller's cancellation.
nonisolated func detachedCancellable<Success: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable @concurrent () async -> Success,
) async -> Success {
    await withTaskGroup(of: Success.self) { group in
        group.addTask(priority: priority, operation: operation)
        // Exactly one child was added, so `next()` always returns its result.
        return await group.next()!
    }
}

/// Throwing variant of `detachedCancellable(priority:_:)`.
nonisolated func detachedCancellable<Success: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable @concurrent () async throws -> Success,
) async throws -> Success {
    try await withThrowingTaskGroup(of: Success.self) { group in
        group.addTask(priority: priority, operation: operation)
        // Exactly one child was added, so `next()` returns its result or rethrows its error.
        return try await group.next()!
    }
}
