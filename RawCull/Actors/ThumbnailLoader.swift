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

    private let maxConcurrent = 6
    private var activeTasks = 0
    private var pendingContinuations: [CheckedContinuation<Void, Never>] = []
    private var cachedSettings: SavedSettings?

    /// Cached settings so we don't hammer the settings actor
    func getSettings() async -> SavedSettings {
        if let cachedSettings { return cachedSettings }
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        cachedSettings = settings
        return settings
    }

    private func acquireSlot() async {
        if activeTasks < maxConcurrent {
            activeTasks += 1
            return
        }
        await withCheckedContinuation { continuation in
            pendingContinuations.append(continuation)
        }
        activeTasks += 1
    }

    private func releaseSlot() {
        activeTasks -= 1
        if let next = pendingContinuations.first {
            pendingContinuations.removeFirst()
            next.resume()
        }
    }

    func thumbnailLoader(file: FileItem) async -> NSImage? {
        await acquireSlot()
        defer { releaseSlot() }

        // Check for cancellation before doing expensive work
        guard !Task.isCancelled else { return nil }

        let settings = await getSettings()
        let cgThumb = await RequestThumbnail().requestThumbnail(
            for: file.url,
            targetSize: settings.thumbnailSizePreview
        )

        guard !Task.isCancelled else { return nil }

        if let cgThumb {
            return NSImage(cgImage: cgThumb, size: .zero)
        }
        return nil
    }
    
    func cancelAll() {
        // Resume all pending continuations so they unfreeze
        // They will then hit the Task.isCancelled check and bail out
        for continuation in pendingContinuations {
            continuation.resume()
        }
        pendingContinuations.removeAll()
        activeTasks = 0  // Reset the counter cleanly
    }
}
