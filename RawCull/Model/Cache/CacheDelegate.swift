//
//  CacheDelegate.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import AppKit
import Foundation
import os

/// Delegate to track NSCache evictions for monitoring memory pressure.
final class CacheDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
    nonisolated static let shared = CacheDelegate()

    /// Synchronous lock-protected counter. Replaces the previous fire-and-forget
    /// `Task { await actor.increment() }` path, which under high eviction churn
    /// fell behind the synchronous delegate fires by 20%+ at sample time.
    private let evictionCount = OSAllocatedUnfairLock(initialState: 0)

    override nonisolated init() {
        super.init()
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let thumb = obj as? CachedThumbnail else { return }
        if cache === SharedMemoryCache.shared.gridThumbnailCache {
            SharedMemoryCache.shared.gridEntryEvicted(cost: thumb.cost)
        } else if cache === SharedMemoryCache.shared.memoryCache {
            SharedMemoryCache.shared.memEntryEvicted(cost: thumb.cost)
            // Record the evicted URL so a subsequent disk-fallback for the
            // same key can be classified as a boomerang miss in diagnostics.
            // Grid-cache evictions are intentionally not tracked.
            if let url = thumb.url {
                SharedMemoryCache.shared.noteEviction(url: url)
            }
        }
        evictionCount.withLock { $0 += 1 }
    }

    nonisolated func getEvictionCount() -> Int {
        evictionCount.withLock { $0 }
    }

    nonisolated func resetEvictionCount() {
        evictionCount.withLock { $0 = 0 }
    }
}
