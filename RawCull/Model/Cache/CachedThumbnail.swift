//
//  CachedThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//
//  Plain reference wrapper for `NSImage` thumbnails held in NSCache.
//
//  Originally `DiscardableThumbnail`, conforming to `NSDiscardableContent` so
//  the OS could purge bitmap pages under memory pressure. Memory Diagnostics
//  measurement (round 3) showed `NSCache` was using that conformance to evict
//  wrappers aggressively at low utilization (~8% of the configured 30 GB
//  cap) — every eviction paired 1:1 with a `discardContentIfPossible` call,
//  collapsing the RAM hit rate to <5%. The wrapper now holds a plain
//  reference so eviction is driven only by our explicit `totalCostLimit` /
//  `countLimit` and the `handleMemoryPressureEvent` handler.
//
import AppKit
import Foundation

final class CachedThumbnail: NSObject, @unchecked Sendable {
    let image: NSImage
    nonisolated let cost: Int
    /// NSURL of the cached item, retained so `CacheDelegate` can identify the
    /// evicted key in `cache(_:willEvictObject:)` (which only receives the
    /// value object). Used to populate `SharedMemoryCache`'s recently-evicted
    /// ring for boomerang-miss diagnostics. Optional for back-compat; nil
    /// disables eviction tracking for that entry.
    nonisolated let url: NSURL?

    nonisolated init(image: NSImage, costPerPixel: Int = 4, url: NSURL? = nil) {
        self.image = image
        self.url = url

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

        super.init()
    }
}
