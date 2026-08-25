import Foundation
import os

nonisolated enum AIInferenceKind: Sendable {
    case similarityIndexing
    case semanticSearch
    case deepReview
}

nonisolated struct ContentionDiagnosticsSnapshot: Equatable, Sendable {
    let coldThumbnailDecodes: Int
    let duplicateThumbnailKeys: Int
    let coalescedThumbnailWaiters: Int
    let thumbnailCancellations: Int
    let activeThumbnailWork: Int
    let peakThumbnailWork: Int
    let similarityInferenceStarts: Int
    let semanticSearchStarts: Int
    let deepReviewInferenceStarts: Int
    let semanticHydrationStarts: Int
    let modelDownloadStarts: Int
    let gridPreloadStarts: Int
    let latestGridCatalogSize: Int
    let latestFirstUsableGridMilliseconds: Int?
}

/// Process-local counters for observing scan, grid, and AI contention.
///
/// This type is intentionally passive: recording an event never changes work
/// scheduling, backend selection, cancellation ownership, or persistent data.
final nonisolated class ContentionDiagnostics: @unchecked Sendable {
    static let shared = ContentionDiagnostics()

    private struct GridPreload {
        let startedAt: Date
        let catalogSize: Int
        var recordedFirstUsableGrid = false
    }

    private struct State {
        var coldThumbnailDecodes = 0
        var duplicateThumbnailKeys = 0
        var coalescedThumbnailWaiters = 0
        var thumbnailCancellations = 0
        var activeThumbnailWork = 0
        var peakThumbnailWork = 0
        var similarityInferenceStarts = 0
        var semanticSearchStarts = 0
        var deepReviewInferenceStarts = 0
        var semanticHydrationStarts = 0
        var modelDownloadStarts = 0
        var gridPreloadStarts = 0
        var latestGridCatalogSize = 0
        var latestFirstUsableGridMilliseconds: Int?
        var gridPreloads: [UUID: GridPreload] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func beginThumbnailWork(coldDecode: Bool) {
        state.withLock { state in
            state.activeThumbnailWork += 1
            state.peakThumbnailWork = max(
                state.peakThumbnailWork,
                state.activeThumbnailWork,
            )
            if coldDecode {
                state.coldThumbnailDecodes += 1
            }
        }
    }

    func endThumbnailWork() {
        state.withLock { state in
            state.activeThumbnailWork = max(0, state.activeThumbnailWork - 1)
        }
    }

    func recordDuplicateThumbnailKey() {
        state.withLock { state in
            state.duplicateThumbnailKeys += 1
            state.coalescedThumbnailWaiters += 1
        }
    }

    func recordThumbnailCancellation() {
        state.withLock { $0.thumbnailCancellations += 1 }
    }

    func recordInferenceStart(_ kind: AIInferenceKind) {
        state.withLock { state in
            switch kind {
            case .similarityIndexing:
                state.similarityInferenceStarts += 1

            case .semanticSearch:
                state.semanticSearchStarts += 1

            case .deepReview:
                state.deepReviewInferenceStarts += 1
            }
        }
    }

    func recordSemanticHydrationStart() {
        state.withLock { $0.semanticHydrationStarts += 1 }
    }

    func recordModelDownloadStart() {
        state.withLock { $0.modelDownloadStarts += 1 }
    }

    func beginGridPreload(catalogSize: Int) -> UUID {
        let id = UUID()
        state.withLock { state in
            state.gridPreloadStarts += 1
            state.latestGridCatalogSize = catalogSize
            state.latestFirstUsableGridMilliseconds = nil
            state.gridPreloads[id] = GridPreload(
                startedAt: Date(),
                catalogSize: catalogSize,
            )
        }
        return id
    }

    func markFirstUsableGrid(preloadID: UUID) {
        state.withLock { state in
            guard var preload = state.gridPreloads[preloadID],
                  !preload.recordedFirstUsableGrid
            else { return }

            preload.recordedFirstUsableGrid = true
            state.gridPreloads[preloadID] = preload
            state.latestGridCatalogSize = preload.catalogSize
            state.latestFirstUsableGridMilliseconds = max(
                0,
                Int(Date().timeIntervalSince(preload.startedAt) * 1000),
            )
        }
    }

    func endGridPreload(preloadID: UUID) {
        _ = state.withLock { $0.gridPreloads.removeValue(forKey: preloadID) }
    }

    func snapshot() -> ContentionDiagnosticsSnapshot {
        state.withLock { state in
            ContentionDiagnosticsSnapshot(
                coldThumbnailDecodes: state.coldThumbnailDecodes,
                duplicateThumbnailKeys: state.duplicateThumbnailKeys,
                coalescedThumbnailWaiters: state.coalescedThumbnailWaiters,
                thumbnailCancellations: state.thumbnailCancellations,
                activeThumbnailWork: state.activeThumbnailWork,
                peakThumbnailWork: state.peakThumbnailWork,
                similarityInferenceStarts: state.similarityInferenceStarts,
                semanticSearchStarts: state.semanticSearchStarts,
                deepReviewInferenceStarts: state.deepReviewInferenceStarts,
                semanticHydrationStarts: state.semanticHydrationStarts,
                modelDownloadStarts: state.modelDownloadStarts,
                gridPreloadStarts: state.gridPreloadStarts,
                latestGridCatalogSize: state.latestGridCatalogSize,
                latestFirstUsableGridMilliseconds: state.latestFirstUsableGridMilliseconds,
            )
        }
    }
}
