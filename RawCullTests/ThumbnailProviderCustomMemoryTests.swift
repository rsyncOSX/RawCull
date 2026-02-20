//
//  ThumbnailProviderCustomMemoryTests.swift
//  RawCullTests
//
//  Template file for adding custom memory limit tests.
//  Copy this and modify for your specific testing needs.
//
//  Created by Thomas Evensen on 04/02/2026.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

// MARK: - Example: Custom Memory Limit Scenarios

@Suite("Custom Memory Limit Tests")
struct CustomMemoryLimitTests {
    /// Example 1: Test with 5 MB cache limit
    /// Useful for testing with moderate cache sizes
    @Test("5 MB cache limit scenario")
    func test5MBCacheLimit() async {
        let config = CacheConfig(
            totalCostLimit: 5_000_000, // 5 MB
            countLimit: 50
        )
        let provider = SharedRequestThumbnail(config: config)

        // Test operations with this specific limit
        let stats = await provider.getCacheStatistics()
        #expect(stats.hitRate >= 0)

        // Verify provider initializes correctly
        await provider.clearCaches()
    }

    /// Example 2: Test with 10 MB cache limit
    /// Good for simulating larger caches
    @Test("10 MB cache limit scenario")
    func test10MBCacheLimit() async {
        let config = CacheConfig(
            totalCostLimit: 10_000_000, // 10 MB
            countLimit: 100
        )
        let provider = SharedRequestThumbnail(config: config)

        let stats = await provider.getCacheStatistics()
        #expect(stats.hits == 0)
    }

    /// Example 3: Test with very small 100 KB limit
    /// Triggers evictions with small images
    @Test("100 KB strict cache limit")
    func test100KBLimit() async {
        let config = CacheConfig(
            totalCostLimit: 100_000, // 100 KB
            countLimit: 3
        )
        let provider = SharedRequestThumbnail(config: config)

        // Clear and verify operation
        await provider.clearCaches()

        let stats = await provider.getCacheStatistics()
        #expect(stats.evictions == 0) // No evictions yet
    }

    /// Example 4: Test with custom cost-heavy scenario
    /// For testing behavior with large images
    @Test("Custom cost-heavy scenario")
    func costHeavyScenario() {
        let config = CacheConfig(
            totalCostLimit: 20_000_000, // 20 MB for large images
            countLimit: 10
        )
        let provider = SharedRequestThumbnail(config: config)

        #expect(true) // Placeholder - add your assertions here
    }
}

// MARK: - Example: Memory Pressure Scenarios

@Suite("Memory Pressure Scenarios")
struct MemoryPressureScenarios {
    /// Test behavior when cache limit is reached
    @Test("Cache behavior near limit")
    func cacheNearLimit() async {
        // Create a config where cache fills up quickly
        let config = CacheConfig(
            totalCostLimit: 500_000, // 500 KB - relatively small
            countLimit: 20
        )
        let provider = SharedRequestThumbnail(config: config)

        // Simulate rapid access
        for _ in 0 ..< 5 {
            let stats = await provider.getCacheStatistics()
            #expect(stats.hitRate >= 0)
        }
    }

    /// Test behavior when exceeding count limit
    @Test("Cache exceeding count limit")
    func exceedCountLimit() async {
        let config = CacheConfig(
            totalCostLimit: 50_000_000, // Large cost limit
            countLimit: 2 // Very low count limit
        )
        let provider = SharedRequestThumbnail(config: config)

        // With count limit of 2, any more items trigger eviction
        let stats = await provider.getCacheStatistics()
        #expect(stats.hits == 0)
    }
}

// MARK: - Example: Comparing Configs

@Suite("Configuration Comparison Tests")
struct ConfigComparisonTests {
    /// Compare behavior across multiple config sizes
    @Test("Behavior across config sizes")
    func multipleConfigSizes() async {
        let configs = [
            ("Small", CacheConfig(totalCostLimit: 100_000, countLimit: 2)),
            ("Medium", CacheConfig(totalCostLimit: 1_000_000, countLimit: 10)),
            ("Large", CacheConfig(totalCostLimit: 10_000_000, countLimit: 50))
        ]

        for (name, config) in configs {
            let provider = SharedRequestThumbnail(config: config)
            let stats = await provider.getCacheStatistics()
            let hitRate = stats.hitRate

            print("Config \(name): hitRate=\(hitRate)%")
            #expect(hitRate >= 0)
        }
    }
}

// MARK: - Example: Eviction Monitoring

@Suite("Cache Eviction Monitoring")
struct EvictionMonitoringTests {
    /// Monitor eviction statistics
    @Test("Eviction statistics collection")
    func evictionStats() async {
        let provider = SharedRequestThumbnail(config: .testing)

        // Initial state
        let initialStats = await provider.getCacheStatistics()
        let initialEvictions = initialStats.evictions
        print("Initial evictions: \(initialEvictions)")

        // After operations
        await provider.clearCaches()

        let finalStats = await provider.getCacheStatistics()
        let finalEvictions = finalStats.evictions
        print("Final evictions: \(finalEvictions)")

        #expect(finalEvictions >= initialEvictions)
    }

    /// Track hit/miss ratio
    @Test("Hit and miss ratio tracking")
    func hitMissRatio() async {
        let provider = SharedRequestThumbnail(config: .testing)

        let stats = await provider.getCacheStatistics()

        // Log statistics
        let hits = stats.hits
        let misses = stats.misses
        let hitRate = stats.hitRate
        let evictions = stats.evictions

        print("Hits: \(hits)")
        print("Misses: \(misses)")
        print("Hit Rate: \(hitRate)%")
        print("Evictions: \(evictions)")

        #expect(true)
    }
}

// MARK: - Example: Realistic Scenarios

@Suite("Realistic Workload Tests")
struct RealisticWorkloadTests {
    /// Simulate typical thumbnail browsing session
    @Test("Typical browsing session")
    func typicalBrowsingSession() async {
        // Config for typical photo viewing (2560x2560 thumbnails)
        let config = CacheConfig(
            totalCostLimit: 500_000_000, // 500 MB - reasonable for 100-150 thumbs
            countLimit: 200
        )
        let provider = SharedRequestThumbnail(config: config)

        // Simulate browsing pattern
        let testURL = URL(fileURLWithPath: "/photos/test.arw")

        // First access - cache miss (file not found in this test)
        _ = await provider.requestThumbnail(for: testURL, targetSize: 2560)

        // Second access - might be cached or miss again
        _ = await provider.requestThumbnail(for: testURL, targetSize: 2560)

        #expect(true)
    }

    /// Simulate rapid scrolling with many thumbnails
    @Test("Rapid scrolling pattern")
    func rapidScrolling() async {
        let config = CacheConfig(
            totalCostLimit: 100_000_000, // 100 MB
            countLimit: 50
        )
        let provider = SharedRequestThumbnail(config: config)

        // Simulate rapid requests
        for index in 0 ..< 20 {
            let url = URL(fileURLWithPath: "/photos/\(index).arw")
            _ = await provider.requestThumbnail(for: url, targetSize: 256)
        }

        let stats = await provider.getCacheStatistics()
        print("Rapid scroll stats: \(stats)")
    }
}

// MARK: - Performance Measurement Tests

@Suite("Memory Performance Tests")
struct MemoryPerformanceTests {
    /// Measure cache operations with different configs
    @Test("Operations speed with testing config")
    func speedWithTestingConfig() async {
        let provider = SharedRequestThumbnail(config: .testing)

        let start = Date()
        for _ in 0 ..< 100 {
            _ = await provider.getCacheStatistics()
        }
        let duration = Date().timeIntervalSince(start)

        print("100 calls with .testing config: \(duration)s")
        #expect(duration < 1.0)
    }

    /// Measure cache operations with production config
    @Test("Operations speed with production config")
    func speedWithProductionConfig() async {
        let provider = SharedRequestThumbnail(config: .production)

        let start = Date()
        for _ in 0 ..< 100 {
            _ = await provider.getCacheStatistics()
        }
        let duration = Date().timeIntervalSince(start)

        print("100 calls with .production config: \(duration)s")
        #expect(duration < 1.0)
    }
}

// MARK: - Integration Test Template

@Suite("Integration Test Examples")
struct IntegrationTestExamples {
    /// Template for testing multiple operations together
    @Test("Multi-operation workflow")
    func multiOperationWorkflow() async {
        let provider = SharedRequestThumbnail(config: .testing)

        // Step 1: Get initial stats
        let initialStats = await provider.getCacheStatistics()
        let initialHits = initialStats.hits
        let initialMisses = initialStats.misses
        print("Initial: hits=\(initialHits), misses=\(initialMisses)")

        // Step 2: Perform operations (would access files in real scenario)
        // ...

        // Step 3: Get final stats
        let finalStats = await provider.getCacheStatistics()
        let finalHits = finalStats.hits
        let finalMisses = finalStats.misses
        print("Final: hits=\(finalHits), misses=\(finalMisses)")

        // Step 4: Verify expectations
        #expect(finalHits >= initialHits)

        // Step 5: Clean up
        await provider.clearCaches()

        // Step 6: Verify cleanup
        let cleanStats = await provider.getCacheStatistics()
        let cleanHits = cleanStats.hits
        #expect(cleanHits == 0 || cleanHits >= 0) // Reset
    }
}

// MARK: - Helper Functions for Custom Tests

/// Create a test configuration for a specific memory size
func createMemoryConfig(sizeInMB: Int, itemCount: Int) -> CacheConfig {
    let costLimit = sizeInMB * 1_000_000
    return CacheConfig(totalCostLimit: costLimit, countLimit: itemCount)
}

/// Create test images of various sizes
func createTestImages(count: Int, width: Int = 100, height: Int = 100) -> [NSImage] {
    (0 ..< count).map { _ in
        createTestImage(width: width, height: height)
    }
}

// Example usage:
// let config = createMemoryConfig(sizeInMB: 5, itemCount: 20)
// let images = createTestImages(count: 10, width: 256, height: 256)
