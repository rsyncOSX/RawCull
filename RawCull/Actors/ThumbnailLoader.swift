//
//  ThumbnailLoader.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import AppKit
import Foundation
import OSLog

/// ThumbnailLoader.swift - A shared, rate-limited thumbnail loader
actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private enum SlotAcquisition {
        case granted
        case cancelled
    }

    private let maxConcurrent = 6
    private var activeTasks = 0
    private var maxObservedActiveTasks = 0
    private var pendingContinuations: [(id: UUID, continuation: CheckedContinuation<SlotAcquisition, Never>)] = []
    private var cachedSettings: SavedSettings?

    /// Cached settings so we don't hammer the settings actor
    func getSettings() async -> SavedSettings {
        if let cachedSettings {
            return cachedSettings
        }
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        cachedSettings = settings
        return settings
    }

    private func acquireSlot() async -> SlotAcquisition {
        guard !Task.isCancelled else { return .cancelled }

        if activeTasks < maxConcurrent {
            activeTasks += 1
            maxObservedActiveTasks = max(maxObservedActiveTasks, activeTasks)
            return .granted
        }

        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: .cancelled)
                    return
                }
                pendingContinuations.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.removeAndResumePendingContinuation(id: id)
            }
        }
    }

    private func removeAndResumePendingContinuation(id: UUID) {
        if let index = pendingContinuations.firstIndex(where: { $0.id == id }) {
            let entry = pendingContinuations.remove(at: index)
            entry.continuation.resume(returning: .cancelled)
        }
    }

    private func releaseSlot() {
        if let next = pendingContinuations.first {
            pendingContinuations.removeFirst()
            // Transfer this real slot directly to the next waiter. Keeping activeTasks
            // unchanged prevents a new caller from over-admitting before the waiter resumes.
            next.continuation.resume(returning: .granted)
            return
        }

        activeTasks = max(activeTasks - 1, 0)
    }

    func thumbnailLoader(file: FileItem, targetSize: Int) async -> NSImage? {
        // Fast path: return from dedicated 200px grid cache without acquiring a slot
        if targetSize <= 200 {
            if let image = cachedGridImage(for: file.url) {
                return image
            }

            // Only grid misses for the catalog currently being preloaded wait.
            // Similarity analysis and requests for other catalogs never pass
            // through this gate.
            guard await ThumbnailPreloadGate.shared.waitUntilGridDecodeIsAvailable(
                for: file.url,
            ) else { return nil }
            guard !Task.isCancelled else { return nil }

            if let image = cachedGridImage(for: file.url) {
                return image
            }
        }

        let acquisition = await acquireSlot()
        guard acquisition == .granted else { return nil }
        defer { releaseSlot() }

        guard !Task.isCancelled else { return nil }

        let settings = await getSettings()
        let requestedSize = targetSize > 0 ? targetSize : settings.thumbnailSizePreview
        let cgThumb = await RequestThumbnail.shared.requestThumbnail(
            for: file.url,
            targetSize: requestedSize,
            purpose: .preview,
        )

        guard !Task.isCancelled else { return nil }

        if let cgThumb {
            return NSImage(cgImage: cgThumb, size: .zero)
        }
        return nil
    }

    private func cachedGridImage(for url: URL) -> NSImage? {
        let gridKey = ThumbnailCacheKey.resolve(
            for: url,
            purpose: .grid,
            requestedPixelSize: 200,
        )
        guard let gridKey else { return nil }
        return SharedMemoryCache.shared.gridObject(forKey: gridKey)?.image
    }

    /// Unblocks all continuations that are waiting for a concurrency slot as cancelled.
    func cancelAll() {
        for entry in pendingContinuations {
            entry.continuation.resume(returning: .cancelled)
        }
        pendingContinuations.removeAll()
    }

    #if DEBUG
        func slotSnapshotForTesting() -> (
            activeTasks: Int,
            pendingContinuations: Int,
            maxConcurrent: Int,
            maxObservedActiveTasks: Int,
        ) {
            (
                activeTasks: activeTasks,
                pendingContinuations: pendingContinuations.count,
                maxConcurrent: maxConcurrent,
                maxObservedActiveTasks: maxObservedActiveTasks,
            )
        }

        func acquireSlotForTesting() async -> Bool {
            await acquireSlot() == .granted
        }

        func releaseSlotForTesting() {
            releaseSlot()
        }
    #endif
}
