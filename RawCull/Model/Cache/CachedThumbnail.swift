//
//  CachedThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//
//  Plain reference wrapper for `NSImage` thumbnails held in NSCache.
//
//  The wrapper holds a plain reference so eviction is driven by the configured
//  `totalCostLimit`, `countLimit`, and explicit memory-pressure handling.
//
import AppKit
import Foundation

/// Sendability invariant: the wrapped `NSImage` must be fully constructed
/// before insertion into cache and treated as immutable afterward. Cache
/// consumers may read the image, but must not mutate representations or draw
/// into it after it crosses a concurrency boundary.
final class CachedThumbnail: NSObject, @unchecked Sendable {
    let image: NSImage
    nonisolated let cost: Int
    nonisolated init(image: NSImage) {
        self.image = image

        // Calculate cost based on actual pixel dimensions from all representations
        // This ensures NSCache accurately tracks RAM footprint for LRU eviction
        var totalCost = 0

        // Sum up all representations' pixel costs (using the project-wide RGBA constant)
        let costPerPixel = SharedMemoryCache.shared.costPerPixel
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

        super.init()
    }
}
