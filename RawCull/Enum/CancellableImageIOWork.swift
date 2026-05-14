//
//  CancellableImageIOWork.swift
//  RawCull
//
//  Created by Codex on 14/05/2026.
//

import Foundation
import os

final class ImageIOCancellationToken: @unchecked Sendable {
    private let cancelled = OSAllocatedUnfairLock(initialState: false)

    nonisolated func cancel() {
        cancelled.withLock { $0 = true }
    }

    nonisolated var isCancelled: Bool {
        cancelled.withLock { $0 }
    }

    nonisolated func checkCancellation() throws {
        if isCancelled || Task.isCancelled {
            throw CancellationError()
        }
    }
}

enum CancellableImageIOWork {
    nonisolated static func run<Success: Sendable>(
        qos: DispatchQoS.QoSClass,
        _ operation: @escaping @Sendable (ImageIOCancellationToken) throws -> Success,
    ) async throws -> Success {
        let token = ImageIOCancellationToken()
        let state = WorkState<Success>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                state.setContinuation(continuation)

                DispatchQueue.global(qos: qos).async {
                    do {
                        try token.checkCancellation()
                        let result = try operation(token)
                        try token.checkCancellation()
                        state.resume(with: .success(result))
                    } catch {
                        state.resume(with: .failure(error))
                    }
                }
            }
        } onCancel: {
            token.cancel()
            state.resume(with: .failure(CancellationError()))
        }
    }

    nonisolated static func runReturningNilOnCancellation<Success: Sendable>(
        qos: DispatchQoS.QoSClass,
        _ operation: @escaping @Sendable (ImageIOCancellationToken) throws -> Success?,
    ) async -> Success? {
        do {
            return try await run(qos: qos, operation)
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }
}

private final class WorkState<Success: Sendable>: @unchecked Sendable {
    private struct State {
        var continuation: CheckedContinuation<Success, any Error>?
        var pendingResult: Result<Success, any Error>?
        var didResume = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    nonisolated func setContinuation(_ continuation: CheckedContinuation<Success, any Error>) {
        let resultToResume = state.withLock { state in
            if state.didResume {
                return Optional<Result<Success, any Error>>.none
            }

            if let pendingResult = state.pendingResult {
                state.didResume = true
                state.pendingResult = nil
                return pendingResult
            }

            state.continuation = continuation
            return nil
        }

        if let resultToResume {
            continuation.resume(with: resultToResume)
        }
    }

    nonisolated func resume(with result: Result<Success, any Error>) {
        let continuationToResume = state.withLock { state in
            if state.didResume {
                return Optional<CheckedContinuation<Success, any Error>>.none
            }

            if let continuation = state.continuation {
                state.didResume = true
                state.continuation = nil
                return continuation
            }

            state.pendingResult = result
            return nil
        }

        continuationToResume?.resume(with: result)
    }
}
