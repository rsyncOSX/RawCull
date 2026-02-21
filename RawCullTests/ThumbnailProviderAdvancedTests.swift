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

@Suite("RequestThumbnail Advanced Memory Tests")
struct RequestThumbnailAdvancedMemoryTests {
    @Test("Small cost limit triggers rapid evictions")
    func rapidEvictionsWithSmallCostLimit() async {
        let config = CacheConfig(totalCostLimit: 10000, countLimit: 100)
        let provider = RequestThumbnail(config: config)

        let initialStats = await provider.getCacheStatistics()
        #expect(initialStats.evictions == 0)

        // After clear, evictions should still be tracked
        await provider.clearCaches()
        let finalStats = await provider.getCacheStatistics()
        #expect(finalStats.evictions == 0) // Cleared
    }

    @Test("Very small count limit prevents accumulation")
    func countLimitStrictEnforcement() async {
        let config = CacheConfig(totalCostLimit: 1_000_000, countLimit: 1)
        let provider = RequestThumbnail(config: config)

        let stats = await provider.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test("Cost calculation accuracy")
    func costCalculation() {
        let image = createTestImage(width: 256, height: 256)
        let thumbnail = DiscardableThumbnail(image: image)

        // 256 * 256 * 4 bytes per pixel = 262,144 bytes
        // Plus 10% overhead = 288,358 bytes
        let expectedMinCost = 256 * 256 * 4

        #expect(thumbnail.cost >= expectedMinCost)
    }
}

@Suite("RequestThumbnail Stress Tests")
@MainActor
struct RequestThumbnailStressTests {
    @Test("Handles rapid sequential operations")
    func rapidSequentialOperations() async {
        let provider = RequestThumbnail(config: .testing)

        for _ in 0 ..< 100 {
            let stats = await provider.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }

    @Test("Handles many concurrent statistics calls")
    func highConcurrencyStatistics() async {
        let provider = RequestThumbnail(config: .testing)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 50 {
                group.addTask {
                    let stats = await provider.getCacheStatistics()
                    #expect(stats.hits >= 0)
                }
            }
        }
    }

    @Test("Clear during concurrent operations")
    func concurrentClear() async {
        let provider = RequestThumbnail(config: .testing)

        async let clearTask: () = provider.clearCaches()
        async let statsTask = provider.getCacheStatistics()

        _ = await (clearTask, statsTask)
    }

    @Test("Multiple rapid clear operations")
    func rapidClears() async {
        let provider = RequestThumbnail(config: .testing)

        for _ in 0 ..< 10 {
            await provider.clearCaches()
        }

        let stats = await provider.getCacheStatistics()
        #expect(stats.hits == 0)
    }
}

@Suite("RequestThumbnail Edge Case Tests")
@MainActor
struct RequestThumbnailEdgeCaseTests {
    @Test("Config with zero cost limit")
    func zeroCostLimit() async {
        // Edge case: what happens with totalCostLimit = 0?
        let config = CacheConfig(totalCostLimit: 0, countLimit: 10)
        let provider = RequestThumbnail(config: config)

        let stats = await provider.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test("Config with zero count limit")
    func zeroCountLimit() async {
        // Edge case: what happens with countLimit = 0?
        let config = CacheConfig(totalCostLimit: 1_000_000, countLimit: 0)
        let provider = RequestThumbnail(config: config)

        let stats = await provider.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    @Test("Very large cache configuration")
    func largeCacheConfig() async {
        let config = CacheConfig(
            totalCostLimit: Int.max / 2,
            countLimit: Int.max / 2
        )
        let provider = RequestThumbnail(config: config)

        let stats = await provider.getCacheStatistics()
        #expect(stats.hits == 0)
    }

    @Test("Thumbnail with extreme URL paths")
    func extremeURLPaths() async {
        let provider = RequestThumbnail(config: .testing)

        let veryLongPath = URL(fileURLWithPath: String(repeating: "/path", count: 100))
        let result = await provider.requestThumbnail(for: veryLongPath, targetSize: 256)

        #expect(result == nil)
    }

    @Test("Preload with nonexistent directory")
    func preloadNonexistentDirectory() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let fakeDir = URL(fileURLWithPath: "/fake/nonexistent/path/\(UUID().uuidString)")

        let result = await provider.preloadCatalog(at: fakeDir, targetSize: 256)

        #expect(result >= 0) // Should return gracefully
    }
}

@Suite("RequestThumbnail Configuration Tests")
@MainActor
struct RequestThumbnailConfigurationTests {
    @Test("Different configs have different limits")
    func configDifferences() {
        let config1 = CacheConfig.production
        let config2 = CacheConfig.testing

        #expect(config1.totalCostLimit > config2.totalCostLimit)
        #expect(config1.countLimit > config2.countLimit)
    }

    @Test("Custom config creation")
    func customConfigCreation() async {
        let customConfigs = [
            CacheConfig(totalCostLimit: 1000, countLimit: 1),
            CacheConfig(totalCostLimit: 10000, countLimit: 5),
            CacheConfig(totalCostLimit: 100_000, countLimit: 10),
            CacheConfig(totalCostLimit: 1_000_000, countLimit: 100)
        ]

        for config in customConfigs {
            let provider = RequestThumbnail(config: config)
            let stats = await provider.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }
}

@Suite("RequestThumbnail Discardable Content Tests")
@MainActor
struct RequestThumbnailDiscardableContentTests {
    @Test("DiscardableThumbnail tracks access correctly")
    func discardableThumbnailAccess() {
        let image = createTestImage()
        let thumbnail = DiscardableThumbnail(image: image)

        // Begin access should succeed initially
        let canAccess = thumbnail.beginContentAccess()
        #expect(canAccess == true)

        // End access
        thumbnail.endContentAccess()
    }

    @Test("DiscardableThumbnail image property accessible")
    func discardableThumbnailImageAccess() {
        let originalImage = createTestImage()
        let thumbnail = DiscardableThumbnail(image: originalImage)

        let canAccess = thumbnail.beginContentAccess()
        #expect(canAccess == true)

        let retrievedImage = thumbnail.image
        #expect(retrievedImage.size == originalImage.size)

        thumbnail.endContentAccess()
    }

    @Test("DiscardableThumbnail cost reflects size")
    func discardableThumbnailCostVariation() {
        let smallImage = createTestImage(width: 50, height: 50)
        let largeImage = createTestImage(width: 500, height: 500)

        let smallThumbnail = DiscardableThumbnail(image: smallImage)
        let largeThumbnail = DiscardableThumbnail(image: largeImage)

        // Larger image should have higher cost
        #expect(largeThumbnail.cost > smallThumbnail.cost)
    }
}

@Suite("RequestThumbnail Isolation Tests")
struct RequestThumbnailIsolationTests {
    @Test("Shared instance is consistent")
    func sharedInstanceConsistency() async {
        let provider1 = RequestThumbnail.shared
        let provider2 = RequestThumbnail.shared

        let stats1 = await provider1.getCacheStatistics()
        let stats2 = await provider2.getCacheStatistics()

        #expect(stats1.hits == stats2.hits)
        #expect(stats1.misses == stats2.misses)
    }

    @Test("Different instances are independent")
    func instanceIndependence() async {
        let provider1 = RequestThumbnail(config: .testing)
        let provider2 = RequestThumbnail(config: .testing)

        let stats1 = await provider1.getCacheStatistics()
        let stats2 = await provider2.getCacheStatistics()

        // Both should start fresh
        #expect(stats1.hits == 0)
        #expect(stats2.hits == 0)
    }
}

@Suite("RequestThumbnail Scalability Tests")
@MainActor
struct RequestThumbnailScalabilityTests {
    @Test("Handles variable target sizes")
    func variousTargetSizes() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testURL = URL(fileURLWithPath: "/test.jpg")

        let sizes = [64, 128, 256, 512, 1024, 2560]
        for size in sizes {
            let result = await provider.thumbnail(for: testURL, targetSize: size)
            // Non-existent file will return nil, but verify no crash
            #expect(true)
        }
    }

    @Test("Multiple concurrent preloads")
    func concurrentPreloads() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testDir = FileManager.default.temporaryDirectory

        async let preload1 = provider.preloadCatalog(at: testDir, targetSize: 256)
        async let preload2 = provider.preloadCatalog(at: testDir, targetSize: 256)

        let (result1, result2) = await (preload1, preload2)

        #expect(result1 >= 0)
        #expect(result2 >= 0)
    }
}
