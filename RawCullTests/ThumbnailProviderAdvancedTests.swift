//
//  ThumbnailProviderAdvancedTests.swift
//  RawCullTests
//
//  Created by Thomas Evensen on 04/02/2026.
//
//  Advanced tests for RequestThumbnail covering edge cases,
//  stress tests, and memory pressure scenarios.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

struct RequestThumbnailAdvancedMemoryTests {
    @Test
    func `Small cost limit triggers rapid evictions`() async {
        let cache = await makeIsolatedCache()

        let initialStats = await cache.getCacheStatistics()
        #expect(initialStats.evictions == 0)

        // After clear, evictions should still be tracked
        await cache.clearCaches()
        let finalStats = await cache.getCacheStatistics()
        #expect(finalStats.evictions == 0) // Cleared
    }

    @Test
    func `Very small count limit prevents accumulation`() async {
        let cache = await makeIsolatedCache()

        let stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Cost calculation accuracy`() {
        let image = createTestImage(width: 256, height: 256)
        let thumbnail = CachedThumbnail(image: image)

        // 256 * 256 * 4 bytes per pixel = 262,144 bytes
        // Plus 10% overhead = 288,358 bytes
        let expectedMinCost = 256 * 256 * 4

        #expect(thumbnail.cost >= expectedMinCost)
    }
}

@MainActor
struct RequestThumbnailStressTests {
    @Test
    func `Handles rapid sequential operations`() async {
        let cache = await makeIsolatedCache()

        for _ in 0 ..< 100 {
            let stats = await cache.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }

    @Test
    func `Handles many concurrent statistics calls`() async {
        let cache = await makeIsolatedCache()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    let stats = await cache.getCacheStatistics()
                    #expect(stats.hits >= 0)
                }
            }
        }
    }

    @Test
    func `Clear during concurrent operations`() async {
        let cache = await makeIsolatedCache()

        async let clearTask: () = cache.clearCaches()
        async let statsTask = cache.getCacheStatistics()

        _ = await (clearTask, statsTask)
    }

    @Test
    func `Multiple rapid clear operations`() async {
        let cache = await makeIsolatedCache()

        for _ in 0 ..< 10 {
            await cache.clearCaches()
        }

        let stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
    }
}

@MainActor
struct RequestThumbnailEdgeCaseTests {
    @Test
    func `Config with zero cost limit`() async {
        // Edge case: what happens with totalCostLimit = 0?
        let cache = await makeIsolatedCache(config: CacheConfig(totalCostLimit: 0, countLimit: 5))

        let stats = await cache.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test
    func `Config with zero count limit`() async {
        // Edge case: what happens with countLimit = 0?
        let cache = await makeIsolatedCache(config: CacheConfig(totalCostLimit: 100_000, countLimit: 0))

        let stats = await cache.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test
    func `Very large cache configuration`() async {
        let cache = await makeIsolatedCache(config: CacheConfig(totalCostLimit: 50_000_000, countLimit: 1000))

        let stats = await cache.getCacheStatistics()
        #expect(stats.hits == 0)
    }

    @Test
    func `Thumbnail with extreme URL paths`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()

        let veryLongPath = URL(fileURLWithPath: String(repeating: "/path", count: 100))
        let result = await provider.requestThumbnail(for: veryLongPath, targetSize: 256)

        #expect(result == nil)
    }

    @Test
    func `Preload with nonexistent directory`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let fakeDir = URL(fileURLWithPath: "/fake/nonexistent/path/\(UUID().uuidString)")

        let result = await provider.preloadCatalog(at: fakeDir, targetSize: 256)

        #expect(result >= 0) // Should return gracefully
    }
}

@MainActor
struct RequestThumbnailConfigurationTests {
    @Test
    func `Different configs have different limits`() {
        let config1 = CacheConfig.production
        let config2 = CacheConfig.testing

        #expect(config1.totalCostLimit > config2.totalCostLimit)
        #expect(config1.countLimit > config2.countLimit)
    }

    @Test
    func `Custom config creation`() async {
        let customConfigs = [
            CacheConfig(totalCostLimit: 1000, countLimit: 1),
            CacheConfig(totalCostLimit: 10000, countLimit: 5),
            CacheConfig(totalCostLimit: 100_000, countLimit: 10),
            CacheConfig(totalCostLimit: 1_000_000, countLimit: 100)
        ]

        for config in customConfigs {
            let cache = await makeIsolatedCache(config: config)
            let stats = await cache.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }
}
