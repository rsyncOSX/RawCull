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

    private nonisolated(unsafe) var _evictionCount = 0
    private let evictionLock = NSLock()

    override nonisolated init() {
        super.init()
    }

    nonisolated func cache(_: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // Check if the evicted object is a DiscardableThumbnail
        if obj is DiscardableThumbnail {
            evictionLock.lock()
            _evictionCount += 1
            evictionLock.unlock()
            Logger.process.debugMessageOnly(
                "CacheDelegate: Evicted DiscardableThumbnail, total evictions: \(_evictionCount)"
            )
        }
    }

    /// Get current eviction count (thread-safe)
    nonisolated func getEvictionCount() -> Int {
        evictionLock.lock()
        defer { evictionLock.unlock() }
        return _evictionCount
    }

    /// Reset eviction count (thread-safe)
    nonisolated func resetEvictionCount() {
        evictionLock.lock()
        defer { evictionLock.unlock() }
        _evictionCount = 0
    }
}
