//
//  CacheDelegate.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import AppKit
import Foundation
import os
import OSLog

/// Delegate to track NSCache evictions for monitoring memory pressure.
final class CacheDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
    nonisolated static let shared = CacheDelegate()

    /// Per-cache eviction counters. Split out from the previous single
    /// `evictionCount` to disambiguate which cache an eviction came from when
    /// the diagnostics TSV shows evictions firing despite plenty of headroom.
    /// `unknownEvictionCount` catches the silent-fallthrough case where the
    /// `===` identity check below matches neither known cache — that path used
    /// to bump the global counter without decrementing either manual counter,
    /// so a non-zero `unk_evictions` column is a hard signal that something
    /// unexpected (a third NSCache, or a swapped reference) is in play.
    private let memEvictionCount = OSAllocatedUnfairLock(initialState: 0)
    private let gridEvictionCount = OSAllocatedUnfairLock(initialState: 0)
    private let unknownEvictionCount = OSAllocatedUnfairLock(initialState: 0)

    override nonisolated init() {
        super.init()
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let thumb = obj as? CachedThumbnail else { return }
        if cache === SharedMemoryCache.shared.gridThumbnailCache {
            SharedMemoryCache.shared.gridEntryEvicted(cost: thumb.cost)
            gridEvictionCount.withLock { $0 += 1 }
            #if DEBUG
                let liveLimit = SharedMemoryCache.shared.gridThumbnailCache.totalCostLimit
                let liveCost = SharedMemoryCache.shared.getGridCacheCurrentCost()
                let liveCount = SharedMemoryCache.shared.getGridCacheCount()
                Logger.process.debugMessageOnly(
                    "EVICT grid url=\(thumb.url?.lastPathComponent ?? "<nil>") cost=\(thumb.cost) " +
                        "liveCost=\(liveCost) liveLimit=\(liveLimit) liveCount=\(liveCount)",
                )
            #endif
        } else if cache === SharedMemoryCache.shared.memoryCache {
            SharedMemoryCache.shared.memEntryEvicted(cost: thumb.cost)
            memEvictionCount.withLock { $0 += 1 }
            // Record the evicted URL so a subsequent disk-fallback for the
            // same key can be classified as a boomerang miss in diagnostics.
            // Grid-cache evictions are intentionally not tracked.
            if let url = thumb.url {
                SharedMemoryCache.shared.noteEviction(url: url)
            }
            #if DEBUG
                let liveLimit = SharedMemoryCache.shared.memoryCache.totalCostLimit
                let liveCost = SharedMemoryCache.shared.getMemoryCacheCurrentCost()
                let liveCount = SharedMemoryCache.shared.getMemoryCacheCount()
                Logger.process.debugMessageOnly(
                    "EVICT mem url=\(thumb.url?.lastPathComponent ?? "<nil>") cost=\(thumb.cost) " +
                        "liveCost=\(liveCost) liveLimit=\(liveLimit) liveCount=\(liveCount)",
                )
            #endif
        } else {
            unknownEvictionCount.withLock { $0 += 1 }
            #if DEBUG
                Logger.process.debugMessageOnly(
                    "EVICT unknown cache=\(ObjectIdentifier(cache).debugDescription) " +
                        "url=\(thumb.url?.lastPathComponent ?? "<nil>") cost=\(thumb.cost)",
                )
            #endif
        }
    }

    /// Sum of per-cache counters. Preserved so existing call sites (TSV
    /// `evictions` column, `getCacheStatistics()`) keep their semantics —
    /// new analyses should read the per-cache getters below.
    nonisolated func getEvictionCount() -> Int {
        getMemEvictionCount() + getGridEvictionCount() + getUnknownEvictionCount()
    }

    nonisolated func getMemEvictionCount() -> Int {
        memEvictionCount.withLock { $0 }
    }

    nonisolated func getGridEvictionCount() -> Int {
        gridEvictionCount.withLock { $0 }
    }

    nonisolated func getUnknownEvictionCount() -> Int {
        unknownEvictionCount.withLock { $0 }
    }

    nonisolated func resetEvictionCount() {
        memEvictionCount.withLock { $0 = 0 }
        gridEvictionCount.withLock { $0 = 0 }
        unknownEvictionCount.withLock { $0 = 0 }
    }
}
