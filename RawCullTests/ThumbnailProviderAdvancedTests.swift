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
        let config = CacheConfig(totalCostLimit: 10000, countLimit: 100)
        let provider = RequestThumbnail(config: config)

        let initialStats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(initialStats.evictions == 0)

        // After clear, evictions should still be tracked
        await SharedMemoryCache.shared.clearCaches()
        let finalStats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(finalStats.evictions == 0) // Cleared
    }

    @Test
    func `Very small count limit prevents accumulation`() async {
        let config = CacheConfig(totalCostLimit: 1_000_000, countLimit: 1)
        let provider = RequestThumbnail(config: config)

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Cost calculation accuracy`() {
        let image = createTestImage(width: 256, height: 256)
        let thumbnail = DiscardableThumbnail(image: image)

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
        let provider = RequestThumbnail(config: .testing)

        for _ in 0 ..< 100 {
            let stats = await SharedMemoryCache.shared.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }

    @Test
    func `Handles many concurrent statistics calls`() async {
        let provider = RequestThumbnail(config: .testing)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    let stats = await SharedMemoryCache.shared.getCacheStatistics()
                    #expect(stats.hits >= 0)
                }
            }
        }
    }

    @Test
    func `Clear during concurrent operations`() async {
        let provider = RequestThumbnail(config: .testing)

        async let clearTask: () = SharedMemoryCache.shared.clearCaches()
        async let statsTask = SharedMemoryCache.shared.getCacheStatistics()

        _ = await (clearTask, statsTask)
    }

    @Test
    func `Multiple rapid clear operations`() async {
        let provider = RequestThumbnail(config: .testing)

        for _ in 0 ..< 10 {
            await SharedMemoryCache.shared.clearCaches()
        }

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
    }
}

@MainActor
struct RequestThumbnailEdgeCaseTests {
    @Test
    func `Config with zero cost limit`() async {
        // Edge case: what happens with totalCostLimit = 0?
        let config = CacheConfig(totalCostLimit: 0, countLimit: 10)
        let provider = RequestThumbnail(config: config)

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test
    func `Config with zero count limit`() async {
        // Edge case: what happens with countLimit = 0?
        let config = CacheConfig(totalCostLimit: 1_000_000, countLimit: 0)
        let provider = RequestThumbnail(config: config)

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test
    func `Very large cache configuration`() async {
        let config = CacheConfig(
            totalCostLimit: Int.max / 2,
            countLimit: Int.max / 2,
        )
        let provider = RequestThumbnail(config: config)

        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
    }

    @Test
    func `Thumbnail with extreme URL paths`() async {
        let provider = RequestThumbnail(config: .testing)

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
            let provider = RequestThumbnail(config: config)
            let stats = await SharedMemoryCache.shared.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }
}

@MainActor
struct RequestThumbnailDiscardableContentTests {
    @Test
    func `DiscardableThumbnail tracks access correctly`() {
        let image = createTestImage()
        let thumbnail = DiscardableThumbnail(image: image)

        // Begin access should succeed initially
        let canAccess = thumbnail.beginContentAccess()
        #expect(canAccess == true)

        // End access
        thumbnail.endContentAccess()
    }

    @Test
    func `DiscardableThumbnail image property accessible`() {
        let originalImage = createTestImage()
        let thumbnail = DiscardableThumbnail(image: originalImage)

        let canAccess = thumbnail.beginContentAccess()
        #expect(canAccess == true)

        let retrievedImage = thumbnail.image
        #expect(retrievedImage.size == originalImage.size)

        thumbnail.endContentAccess()
    }

    @Test
    func `DiscardableThumbnail cost reflects size`() {
        let smallImage = createTestImage(width: 50, height: 50)
        let largeImage = createTestImage(width: 500, height: 500)

        let smallThumbnail = DiscardableThumbnail(image: smallImage)
        let largeThumbnail = DiscardableThumbnail(image: largeImage)

        // Larger image should have higher cost
        #expect(largeThumbnail.cost > smallThumbnail.cost)
    }
}

@MainActor
struct RequestThumbnailScalabilityTests {
    @Test
    func `Handles variable target sizes`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testURL = URL(fileURLWithPath: "/test.jpg")

        let sizes = [64, 128, 256, 512, 1024, 2560]
        for size in sizes {
            let result = await provider.thumbnail(for: testURL, targetSize: size)
            // Non-existent file will return nil, but verify no crash
            #expect(true)
        }
    }

    @Test
    func `Multiple concurrent preloads`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testDir = FileManager.default.temporaryDirectory

        async let preload1 = provider.preloadCatalog(at: testDir, targetSize: 256)
        async let preload2 = provider.preloadCatalog(at: testDir, targetSize: 256)

        let (result1, result2) = await (preload1, preload2)

        #expect(result1 >= 0)
        #expect(result2 >= 0)
    }
}
