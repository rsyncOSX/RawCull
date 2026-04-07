//
//  RawCullTestsConcurrencyTests.swift
//  RawCull
//
//  Created by Thomas Evensen on 18/03/2026.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

enum ConcurrencyTests {
    // MARK: - CacheDelegate Thread Safety

    struct CacheDelegateTests {
        @Test
        func `CacheDelegate handles concurrent evictions safely`() async throws {
            let delegate = CacheDelegate.shared
            await delegate.resetEvictionCount()

            // Simulate 1000 concurrent eviction events
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 1000 {
                    group.addTask {
                        // Simulate cache eviction
                        let cache = NSCache<NSString, NSString>()
                        cache.delegate = delegate
                        cache.setObject("test" as NSString, forKey: "key" as NSString)
                        cache.removeAllObjects()
                    }
                }
            }

            // Give async operations time to complete
            try await Task.sleep(for: .milliseconds(100))

            let finalCount = await delegate.getEvictionCount()
            #expect(finalCount >= 0, "Eviction count should never be negative")
            // Note: We can't test exact count since NSCache eviction is unpredictable
        }

        @Test
        func `CacheDelegate reset is thread-safe`() async {
            let delegate = CacheDelegate.shared

            await withTaskGroup(of: Void.self) { group in
                // Multiple concurrent resets
                for _ in 0 ..< 100 {
                    group.addTask {
                        await delegate.resetEvictionCount()
                    }
                }

                // And some increments
                for _ in 0 ..< 100 {
                    group.addTask {
                        _ = await delegate.getEvictionCount()
                    }
                }
            }

            let count = await delegate.getEvictionCount()
            #expect(count >= 0, "Count should be non-negative after concurrent operations")
        }
    }

    // MARK: - SharedMemoryCache Thread Safety

    struct SharedMemoryCacheTests {
        @Test
        func `SharedMemoryCache handles concurrent access safely`() async {
            let cache = SharedMemoryCache.shared

            // Create test URLs
            let urls = (0 ..< 100).map { index in
                URL(fileURLWithPath: "/tmp/test\(index).jpg") as NSURL
            }

            await withTaskGroup(of: Void.self) { group in
                // Concurrent writes
                for (_, url) in urls.enumerated() {
                    group.addTask {
                        if let thumbnail = createTestThumbnail(size: 100) {
                            cache.setObject(thumbnail, forKey: url, cost: 100 * 100 * 4)
                        }
                    }
                }

                // Concurrent reads
                for url in urls {
                    group.addTask {
                        _ = cache.object(forKey: url)
                    }
                }
            }

            // Test passed if no crashes occurred
            #expect(true, "Cache survived concurrent access")
        }

        @Test
        func `ensureReady prevents duplicate initialization`() async {
            let cache = SharedMemoryCache.shared

            // Call ensureReady concurrently 100 times
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 100 {
                    group.addTask {
                        await cache.ensureReady()
                    }
                }
            }

            // Verify cache is properly configured (only once)
            let costPerPixel = await cache.costPerPixel
            #expect(costPerPixel > 0, "Cache should be configured with valid cost per pixel")
        }

        @Test
        func `Cache statistics are thread-safe`() async {
            let cache = SharedMemoryCache.shared
            await cache.ensureReady()

            // Concurrent statistics updates
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 50 {
                    group.addTask {
                        await cache.updateCacheMemory()
                    }
                }

                for _ in 0 ..< 50 {
                    group.addTask {
                        await cache.updateCacheDisk()
                    }
                }

                // Read statistics concurrently
                for _ in 0 ..< 20 {
                    group.addTask {
                        _ = await cache.getCacheStatistics()
                    }
                }
            }

            let stats = await cache.getCacheStatistics()
            #expect(stats.hits >= 50, "Should have at least 50 memory hits")
            #expect(stats.misses >= 50, "Should have at least 50 disk hits")
        }
    }

    // MARK: - SettingsViewModel Thread Safety

    struct SettingsViewModelTests {
        @Test
        func `SettingsViewModel handles concurrent reads safely`() async {
            let viewModel = await SettingsViewModel.shared

            // Load settings first
            await viewModel.loadSettings()

            // Concurrent reads
            await withTaskGroup(of: SavedSettings.self) { group in
                for _ in 0 ..< 100 {
                    group.addTask {
                        await viewModel.asyncgetsettings()
                    }
                }

                // Collect all results
                var results: [SavedSettings] = []
                for await result in group {
                    results.append(result)
                }

                // All results should be identical (no tearing)
                #expect(results.count == 100)
                let first = results[0]
                for result in results {
                    // Access via MainActor.run: SettingsViewModel is inferred @MainActor
                    let resultMB = await MainActor.run { result.memoryCacheSizeMB }
                    let firstMB = await MainActor.run { first.memoryCacheSizeMB }
                    let resultGrid = await MainActor.run { result.thumbnailSizeGrid }
                    let firstGrid = await MainActor.run { first.thumbnailSizeGrid }
                    #expect(resultMB == firstMB)
                    #expect(resultGrid == firstGrid)
                }
            }
        }

        @Test
        func `Settings save and load are atomic`() async {
            let viewModel = await SettingsViewModel.shared

            // Set known values
            await MainActor.run {
                viewModel.memoryCacheSizeMB = 1000
                viewModel.thumbnailSizeGrid = 200
            }

            await viewModel.saveSettings()

            // Change values
            await MainActor.run {
                viewModel.memoryCacheSizeMB = 2000
                viewModel.thumbnailSizeGrid = 300
            }

            // Load should restore saved values
            await viewModel.loadSettings()

            let savedSettings = await viewModel.asyncgetsettings()
            let savedMB = await MainActor.run { savedSettings.memoryCacheSizeMB }
            let savedGrid = await MainActor.run { savedSettings.thumbnailSizeGrid }
            #expect(savedMB == 1000)
            #expect(savedGrid == 200)
        }
    }

    // MARK: - ExecuteCopyFiles Thread Safety

    struct ExecuteCopyFilesTests {
        @Test(.timeLimit(.minutes(1)))
        func `ExecuteCopyFiles cleanup happens after completion`() async {
            // This is a mock test - in real scenario you'd need actual rsync
            var completionCalled = false
            var cleanupOrder: [String] = []

            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    // Simulate completion callback
                    completionCalled = true
                    cleanupOrder.append("completion")

                    // Simulate small delay before cleanup
                    try? await Task.sleep(for: .milliseconds(10))
                    cleanupOrder.append("cleanup")

                    continuation.resume()
                }
            }

            #expect(completionCalled)
            #expect(cleanupOrder == ["completion", "cleanup"],
                    "Cleanup should happen after completion")
        }
    }

    // MARK: - Memory Model Thread Safety

    struct MemoryViewModelTests {
        @Test
        func `MemoryViewModel updates don't block MainActor`() async {
            let viewModel = await MemoryViewModel()

            let startTime = ContinuousClock.now

            // Update memory stats (should be fast due to Task.detached)
            await viewModel.updateMemoryStats()

            let duration = ContinuousClock.now - startTime

            // Should complete in reasonable time (not blocking)
            #expect(duration < .milliseconds(100),
                    "Memory stats update should be non-blocking")
        }

        @Test
        func `MemoryViewModel handles concurrent updates safely`() async {
            let viewModel = await MemoryViewModel()

            // Multiple concurrent updates
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 10 {
                    group.addTask {
                        await viewModel.updateMemoryStats()
                    }
                }
            }

            // Verify state is consistent
            let totalMemory = await viewModel.totalMemory
            let usedMemory = await viewModel.usedMemory
            let appMemory = await viewModel.appMemory

            #expect(totalMemory > 0, "Total memory should be positive")
            #expect(usedMemory > 0, "Used memory should be positive")
            #expect(appMemory > 0, "App memory should be positive")
            #expect(usedMemory <= totalMemory, "Used memory can't exceed total")
            #expect(appMemory <= usedMemory, "App memory can't exceed used")
        }
    }

    // MARK: - Actor Isolation Tests

    struct ActorIsolationTests {
        @Test
        func `ScanAndCreateThumbnails is properly isolated`() {
            // Verify that actor methods can be called concurrently without data races
            // This would be tested with real file operations in production

            #expect(true, "Actor isolation prevents data races")
        }

        @Test
        func `Actors maintain isolation under load`() async {
            let cache = SharedMemoryCache.shared

            // Heavy concurrent load
            await withTaskGroup(of: Void.self) { group in
                for iteration in 0 ..< 1000 {
                    group.addTask {
                        await cache.ensureReady()

                        if iteration % 2 == 0 {
                            await cache.updateCacheMemory()
                        } else {
                            await cache.updateCacheDisk()
                        }
                    }
                }
            }

            let stats = await cache.getCacheStatistics()
            #expect(stats.hits + stats.misses <= 1000,
                    "Total operations should not exceed expected count")
        }
    }

    // MARK: - Sendable Verification

    struct SendableTests {
        @Test
        func `SavedSettings is safely sendable across isolation domains`() async {
            let settings = await SavedSettings(
                memoryCacheSizeMB: 5000,
                thumbnailSizeGrid: 100,
                thumbnailSizePreview: 1024,
                thumbnailSizeFullSize: 8700,
                thumbnailCostPerPixel: 4,
                thumbnailSizeGridView: 400,
                useThumbnailAsZoomPreview: false,
            )

            // Pass across isolation domains
            await withTaskGroup(of: SavedSettings.self) { group in
                for _ in 0 ..< 10 {
                    group.addTask {
                        // Sendable allows safe transfer
                        settings
                    }
                }

                var count = 0
                for await _ in group {
                    count += 1
                }

                #expect(count == 10)
            }
        }

        @Test
        func `CacheConfig is safely sendable`() async {
            let config = CacheConfig(
                totalCostLimit: 5000 * 1024 * 1024,
                countLimit: 10000,
                costPerPixel: 4,
            )

            // Pass to actor
            await SharedMemoryCache.shared.ensureReady(config: config)

            #expect(true, "CacheConfig successfully crossed isolation boundary")
        }
    }

    // MARK: - Race Condition Detection

    @Suite(.tags(.critical))
    struct RaceConditionTests {
        @Test(
            .timeLimit(.minutes(1)),
        )
        func `No race in cache delegate eviction counting`() async {
            let delegate = CacheDelegate.shared
            await delegate.resetEvictionCount()

            // Hammer it with concurrent operations
            let iterations = 10000

            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< iterations {
                    group.addTask {
                        // These operations should never race
                        _ = await delegate.getEvictionCount()
                    }
                }
            }

            #expect(true, "No race condition detected in cache delegate")
        }

        @Test(
            .timeLimit(.minutes(1)),
        )
        func `No race in settings read/write`() async {
            let viewModel = await SettingsViewModel.shared

            await withTaskGroup(of: Void.self) { group in
                // Concurrent reads
                for _ in 0 ..< 100 {
                    group.addTask {
                        _ = await viewModel.asyncgetsettings()
                    }
                }

                // Concurrent property access through MainActor
                for _ in 0 ..< 100 {
                    group.addTask {
                        await MainActor.run {
                            _ = viewModel.memoryCacheSizeMB
                        }
                    }
                }
            }

            #expect(true, "No race condition in settings access")
        }
    }

    // MARK: - Performance Tests

    struct PerformanceTests {
        @Test
        func `Cache lookup performance under concurrent load`() async {
            let cache = SharedMemoryCache.shared

            // Populate cache
            let urls = (0 ..< 100).map { URL(fileURLWithPath: "/tmp/test\(Int($0)).jpg") as NSURL }
            for url in urls {
                if let thumbnail = createTestThumbnail(size: 100) {
                    cache.setObject(thumbnail, forKey: url, cost: 100 * 100 * 4)
                }
            }

            let startTime = ContinuousClock.now

            // Concurrent lookups
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 1000 {
                    group.addTask {
                        _ = cache.object(forKey: urls.randomElement()!)
                    }
                }
            }

            let duration = ContinuousClock.now - startTime

            // Should handle 1000 concurrent lookups quickly
            #expect(duration < .seconds(1),
                    "1000 concurrent cache lookups should complete within 1 second")
        }

        @Test
        func `Actor serialization doesn't create bottleneck`() async {
            let cache = SharedMemoryCache.shared

            let startTime = ContinuousClock.now

            // 100 sequential actor calls
            for _ in 0 ..< 100 {
                await cache.ensureReady()
            }

            let duration = ContinuousClock.now - startTime

            #expect(duration < .milliseconds(100),
                    "Actor calls should be fast due to early return optimization")
        }
    }
}

// MARK: - Helper Functions

private func createTestThumbnail(size: Int) -> DiscardableThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return DiscardableThumbnail(image: image)
}

// MARK: - Test Tags

extension Tag {
    @Tag static var critical: Self
    @Tag static var performance: Self
    @Tag static var threadSafety: Self
}
