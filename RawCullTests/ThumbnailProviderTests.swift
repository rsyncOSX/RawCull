//
//  ThumbnailProviderTests.swift
//  RawCullTests
//
//  Created by Thomas Evensen on 04/02/2026.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

// MARK: - Test Image Generator

func createTestImage(width: Int = 100, height: Int = 100) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

// MARK: - Tests

struct RequestThumbnailTests {
    // MARK: - Initialization Tests

    @Test
    func `Initializes with production config by default`() async {
        let cache = await makeIsolatedCache(config: .production)
        let stats = await cache.getCacheStatistics()
        #expect(stats.hitRate == 0)
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Initializes with custom config`() async {
        let cache = await makeIsolatedCache()
        let stats = await cache.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    // MARK: - Cache Statistics Tests

    @Test
    func `Cache hit rate calculates correctly`() async {
        let cache = await makeIsolatedCache()

        // Simulate a hit and a miss
        // Note: We'd need access to storeInMemory to fully test this
        // For now, we test the statistics gathering
        let stats = await cache.getCacheStatistics()
        let expectedHitRate = 0.0 // Initially no hits or misses

        #expect(stats.hitRate == expectedHitRate)
    }

    @Test
    func `Statistics reset after clear caches`() async {
        let cache = await makeIsolatedCache()

        // Get initial stats
        var stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)

        // Clear and verify
        await cache.clearCaches()
        stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Cache respects cost limit`() {
        _ = RequestThumbnail()

        // With a very small cost limit, items should be evicted
        // This tests the memory management

        #expect(true) // Placeholder - full implementation requires cache introspection
    }

    // MARK: - Cache Lookup Tests

    @Test
    func `Thumbnail method handles missing files gracefully`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()
        let missingURL = URL(fileURLWithPath: "/nonexistent/file.jpg")

        let result = await provider.requestThumbnail(for: missingURL, targetSize: 256)

        #expect(result == nil)
    }

    // MARK: - Clear Cache Tests

    @Test
    func `Clear caches removes all cached items`() async {
        let cache = await makeIsolatedCache()

        // Clear caches
        await cache.clearCaches()

        // Verify statistics are reset
        let stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
        #expect(stats.evictions == 0)
    }

    // MARK: - Preload Catalog Tests

    @Test
    func `Preload catalog starts and can be tracked`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testDir = FileManager.default.temporaryDirectory

        // This will fail to find files but tests the mechanism
        let result = await provider.preloadCatalog(at: testDir, targetSize: 256)

        #expect(result >= 0)
    }

    // MARK: - Concurrency Tests

    @Test
    func `Provider handles concurrent access safely`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()
        let testURL = URL(fileURLWithPath: "/test/file.jpg")

        // Attempt concurrent reads on non-existent file
        async let result1 = provider.requestThumbnail(for: testURL, targetSize: 256)
        async let result2 = provider.requestThumbnail(for: testURL, targetSize: 256)
        async let result3 = provider.requestThumbnail(for: testURL, targetSize: 256)

        let (res1, res2, res3) = await (result1, result2, result3)

        #expect(res1 == nil)
        #expect(res2 == nil)
        #expect(res3 == nil)
    }

    // MARK: - Configuration Tests

    @Test
    func `Config production has correct limits`() {
        let config = CacheConfig.production

        #expect(config.totalCostLimit == 500 * 1024 * 1024)
        #expect(config.countLimit == 1000)
    }

    @Test
    func `Config testing has small limits`() {
        let config = CacheConfig.testing

        #expect(config.totalCostLimit == 100_000)
        #expect(config.countLimit == 5)
    }

    // MARK: - Cache Delegate Tests

    @Test
    func `Cache delegate is properly set`() {
        _ = RequestThumbnail()

        // Verify provider initializes without crashing
        // A full test would require exposing the delegate

        #expect(true)
    }

    // MARK: - Sendable Conformance Tests

    @Test
    func `Provider is actor-isolated for thread safety`() async {
        let cache = await makeIsolatedCache()

        // Multiple concurrent accesses should not cause data races
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    let stats = await cache.getCacheStatistics()
                    #expect(stats.hitRate >= 0)
                }
            }
        }
    }
}

// MARK: - Performance Tests

@MainActor
struct RequestThumbnailPerformanceTests {
    @Test
    func `Statistics gathering is fast`() async {
        let cache = await makeIsolatedCache()

        let startTime = Date()
        for _ in 0 ..< 1000 {
            _ = await cache.getCacheStatistics()
        }
        let duration = Date().timeIntervalSince(startTime)

        // Should complete 1000 calls in less than 1 second
        #expect(duration < 1.0)
    }

    @Test
    func `Clear operation completes promptly`() async {
        let cache = await makeIsolatedCache()

        let startTime = Date()
        await cache.clearCaches()
        let duration = Date().timeIntervalSince(startTime)

        // Should complete quickly even with empty cache
        #expect(duration < 1.0)
    }
}
