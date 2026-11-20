//
//  extension+Task+Detached.swift
//  RawCull
//
//  `Task.detached` keeps blocking file and image work off the caller's actor,
//  but a detached task does not inherit the caller's cancellation. Awaiting
//  `.value` therefore keeps a decode or sharpen running after the request that
//  wanted it (a catalog switch, a cancelled preload) is gone. These helpers run
//  the work detached and forward the caller's cancellation to it; the work
//  itself should check `Task.isCancelled` before its expensive step.
//

import Foundation

/// Runs `operation` in a detached task and cancels it if the caller is cancelled.
nonisolated func detachedCancellable<Success: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable @concurrent () async -> Success,
) async -> Success {
    let task = Task.detached(priority: priority, operation: operation)
    return await withTaskCancellationHandler {
        await task.value
    } onCancel: {
        task.cancel()
    }
}

/// Throwing variant of `detachedCancellable(priority:_:)`.
nonisolated func detachedCancellable<Success: Sendable>(
    priority: TaskPriority? = nil,
    _ operation: @escaping @Sendable @concurrent () async throws -> Success,
) async throws -> Success {
    let task = Task.detached(priority: priority, operation: operation)
    return try await withTaskCancellationHandler {
        try await task.value
    } onCancel: {
        task.cancel()
    }
}
