//
//  CacheDelegate.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import AppKit
import Foundation

/// Delegate to track NSCache evictions for monitoring memory pressure
final class CacheDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
    nonisolated static let shared = CacheDelegate()

    /// Actor to safely manage eviction count
    private let evictionCounter = EvictionCounter()

    override nonisolated init() {
        super.init()
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let thumb = obj as? DiscardableThumbnail else { return }
        if cache === SharedMemoryCache.shared.gridThumbnailCache {
            SharedMemoryCache.shared.gridEntryEvicted(cost: thumb.cost)
        } else if cache === SharedMemoryCache.shared.memoryCache {
            SharedMemoryCache.shared.memEntryEvicted(cost: thumb.cost)
        }
        Task { await evictionCounter.increment() }
    }

    /// Get current eviction count (thread-safe)
    func getEvictionCount() async -> Int {
        await evictionCounter.getCount()
    }

    /// Reset eviction count (thread-safe)
    func resetEvictionCount() async {
        await evictionCounter.reset()
    }
}

/// Actor to safely track eviction count
private actor EvictionCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func getCount() -> Int {
        count
    }

    func reset() {
        count = 0
    }
}
