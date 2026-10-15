import Foundation

/// Prevents grid misses for the actively preloading catalog from starting a
/// second thumbnail decode. Other catalogs and every AI workflow remain
/// independent of this gate.
actor ThumbnailPreloadGate {
    static let shared = ThumbnailPreloadGate()

    private struct Waiter {
        let sourceURL: URL
        let continuation: CheckedContinuation<Bool, Never>
    }

    private var activeCatalogs: [UUID: URL] = [:]
    private var completedFiles: [UUID: Set<URL>] = [:]
    private var waiters: [UUID: Waiter] = [:]

    func begin(catalogURL: URL) -> UUID {
        let id = UUID()
        activeCatalogs[id] = catalogURL.standardizedFileURL
        completedFiles[id] = []
        return id
    }

    func end(_ id: UUID) {
        activeCatalogs.removeValue(forKey: id)
        completedFiles.removeValue(forKey: id)
        resumeEligibleWaiters()
    }

    /// Release this file's waiters after the native read has finished, including
    /// a failed decode so the interactive path can retry it. Other files remain gated.
    func finished(sourceURL: URL, sessionID: UUID) {
        let source = sourceURL.standardizedFileURL
        guard activeCatalogs[sessionID]?.path == source.deletingLastPathComponent().path else { return }
        completedFiles[sessionID, default: []].insert(source)
        resumeEligibleWaiters()
    }

    func waitUntilGridDecodeIsAvailable(for sourceURL: URL) async -> Bool {
        guard isBlocked(sourceURL) else { return true }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: false)
                    return
                }
                waiters[id] = Waiter(
                    sourceURL: sourceURL.standardizedFileURL,
                    continuation: continuation,
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id)
            }
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: false)
    }

    private func resumeEligibleWaiters() {
        let eligibleIDs = waiters.compactMap { id, waiter in
            isBlocked(waiter.sourceURL) ? nil : id
        }
        for id in eligibleIDs {
            guard let waiter = waiters.removeValue(forKey: id) else { continue }
            waiter.continuation.resume(returning: true)
        }
    }

    private func isBlocked(_ sourceURL: URL) -> Bool {
        let source = sourceURL.standardizedFileURL
        let sourceCatalog = source.deletingLastPathComponent()
        return activeCatalogs.contains { id, catalog in
            catalog.path == sourceCatalog.path && completedFiles[id]?.contains(source) != true
        }
    }
}
