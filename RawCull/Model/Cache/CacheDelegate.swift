//
//  CacheDelegate.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/02/2026.
//

import AppKit
import Foundation
import OSLog

/// Delegate to track NSCache evictions for monitoring memory pressure
final class CacheDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
    nonisolated static let shared = CacheDelegate()
    
    // Actor to safely manage eviction count
    private let evictionCounter = EvictionCounter()

    override nonisolated init() {
        super.init()
    }

    nonisolated func cache(_: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // Check if the evicted object is a DiscardableThumbnail
        if obj is DiscardableThumbnail {
            Task {
                let count = await evictionCounter.increment()
                Logger.process.debugMessageOnly(
                    "CacheDelegate: Evicted DiscardableThumbnail, total evictions: \(count)",
                )
            }
        }
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
    
    func increment() -> Int {
        count += 1
        return count
    }
    
    func getCount() -> Int {
        count
    }
    
    func reset() {
        count = 0
    }
}

