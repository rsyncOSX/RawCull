//
//  DiscardableThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//
import AppKit
import Foundation
import os
import OSLog

final class DiscardableThumbnail: NSObject, NSDiscardableContent, @unchecked Sendable {
    let image: NSImage
    nonisolated let cost: Int
    private let state = OSAllocatedUnfairLock(initialState: (isDiscarded: false, accessCount: 0))

    nonisolated init(image: NSImage, costPerPixel: Int = 4) {
        self.image = image

        // Calculate cost based on actual pixel dimensions from all representations
        // This ensures NSCache accurately tracks RAM footprint for LRU eviction
        var totalCost = 0

        // Sum up all representations' pixel costs (using configured bytes per pixel)
        for rep in image.representations {
            let pixelCost = rep.pixelsWide * rep.pixelsHigh * costPerPixel
            totalCost += pixelCost
        }

        // If no representations found, fall back to logical size estimate
        // WARNING: On Retina (2x) or high-DPI displays, image.size is in logical points
        // For accurate pixel count on all displays, prefer using image.representations when available
        if totalCost == 0 {
            let width = Int(image.size.width)
            let height = Int(image.size.height)
            totalCost = width * height * costPerPixel
        }

        // Add overhead buffer (~10%) for NSImage wrapper and caching metadata
        cost = Int(Double(totalCost) * 1.1)

        Logger.process.debugMessageOnly(
            "DiscardableThumbnail: computed Cost \(cost) for image of \(image.size)"
        )

        super.init()
    }

    nonisolated func beginContentAccess() -> Bool {
        state.withLock {
            if $0.isDiscarded { return false }
            $0.accessCount += 1
            return true
        }
    }

    nonisolated func endContentAccess() {
        state.withLock { $0.accessCount = max(0, $0.accessCount - 1) }
    }

    nonisolated func discardContentIfPossible() {
        state.withLock { if $0.accessCount == 0 { $0.isDiscarded = true } }
    }

    nonisolated func isContentDiscarded() -> Bool {
        state.withLock { $0.isDiscarded }
    }
}
