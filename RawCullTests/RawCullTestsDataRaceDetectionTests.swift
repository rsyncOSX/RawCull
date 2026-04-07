//
//  RawCullTestsDataRaceDetectionTests.swift
//  RawCull
//
//  Created by Thomas Evensen on 18/03/2026.
//
//  These tests are designed to work with Thread Sanitizer (TSan)
//  Run with: Product > Scheme > Edit Scheme > Test > Diagnostics > Thread Sanitizer
//

import AppKit
import Foundation
@testable import RawCull
import Testing

@Suite(
    .tags(.threadSafety),
)
struct DataRaceDetectionTests {
    // MARK: - Shared State Access Tests

    @Test(
        .bug("https://github.com/yourusername/rawcull/issues/1", "Pressure level accessed from multiple threads"),
    )
    func `No data race in SharedMemoryCache.currentPressureLevel`() async {
        let cache = SharedMemoryCache.shared

        // Read from multiple threads simultaneously
        await withTaskGroup(of: SharedMemoryCache.MemoryPressureLevel.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    // This is marked nonisolated(unsafe) but only written from DispatchSource
                    // Multiple reads should be safe
                    cache.currentPressureLevel
                }
            }

            var levels: [SharedMemoryCache.MemoryPressureLevel] = []
            for await level in group {
                levels.append(level)
            }

            // All reads completed without TSan errors
            #expect(levels.count == 100)
        }
    }

    @Test
    func `No data race in NSCache access through SharedMemoryCache`() async {
        let cache = SharedMemoryCache.shared

        let urls = (0 ..< 100).map { URL(fileURLWithPath: "/tmp/test\(Int($0)).jpg") as NSURL }

        // Concurrent writes and reads (NSCache is documented as thread-safe)
        await withTaskGroup(of: Void.self) { group in
            // Writers
            for (_, url) in urls.enumerated() {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 100) {
                        cache.setObject(thumbnail, forKey: url, cost: 100 * 100 * 4)
                    }
                }
            }

            // Readers
            for url in urls {
                group.addTask {
                    _ = cache.object(forKey: url)
                }
            }

            // Deleters
            group.addTask {
                cache.removeAllObjects()
            }
        }

        #expect(true, "NSCache handled concurrent access without data races")
    }

    // MARK: - Actor State Protection Tests

    @Test
    func `Actor state is never accessed concurrently`() async {
        let cache = SharedMemoryCache.shared

        // These calls are serialized by the actor
        await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 1000 {
                group.addTask {
                    await cache.costPerPixel
                }
            }

            var values: [Int] = []
            for await value in group {
                values.append(value)
            }

            // All values should be valid (actor prevents torn reads)
            #expect(values.allSatisfy { $0 > 0 })
        }
    }

    @Test
    func `Actor prevents concurrent mutation of setupTask`() async {
        let cache = SharedMemoryCache.shared

        // Multiple concurrent calls - actor ensures no concurrent mutation
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 500 {
                group.addTask {
                    await cache.ensureReady()
                }
            }
        }

        #expect(true, "setupTask mutation is protected by actor")
    }

    // MARK: - Observable Property Access Tests

    @Test
    func `SettingsViewModel @Observable properties protected by MainActor`() async {
        let viewModel = await SettingsViewModel.shared

        // All accesses through MainActor
        await withTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    await MainActor.run {
                        viewModel.memoryCacheSizeMB
                    }
                }
            }

            var values: [Int] = []
            for await value in group {
                values.append(value)
            }

            // All reads should be consistent
            let first = values[0]
            #expect(values.allSatisfy { $0 == first },
                    "MainActor prevents concurrent access")
        }
    }

    @Test
    func `asyncgetsettings creates isolated snapshot`() async {
        let viewModel = await SettingsViewModel.shared

        // Take snapshot
        let snapshot1 = await viewModel.asyncgetsettings()

        // Modify settings
        await MainActor.run {
            viewModel.memoryCacheSizeMB = 9999
        }

        // Old snapshot should be unchanged (value semantics)
        // Access via MainActor.run: SettingsViewModel is inferred @MainActor, so
        // properties named memoryCacheSizeMB are treated as main-actor-isolated
        let snapshotMB = await MainActor.run { snapshot1.memoryCacheSizeMB }
        #expect(snapshotMB != 9999,
                "Snapshot is isolated from subsequent changes")
    }

    // MARK: - Weak Reference Safety Tests

    @Test
    func `Weak references don't cause use-after-free`() async throws {
        // Test the weak capture pattern in DispatchSource handlers

        actor TestActor {
            var value = 0

            func increment() {
                value += 1
            }
        }

        var actor: TestActor? = TestActor()
        weak let weakActor = actor

        let handler: @Sendable () -> Void = {
            guard let strongActor = weakActor else { return }
            Task {
                await strongActor.increment()
            }
        }

        handler()
        try await Task.sleep(for: .milliseconds(10))

        let value1 = await actor?.value
        #expect(value1 == 1)

        // Release the actor
        actor = nil

        // Handler should safely handle nil
        handler()
        try await Task.sleep(for: .milliseconds(10))

        #expect(weakActor == nil, "Weak reference correctly became nil")
    }

    // MARK: - Sendable Conformance Tests

    @Test
    func `SavedSettings is truly Sendable`() async {
        let settings = await SavedSettings(
            memoryCacheSizeMB: 5000,
            thumbnailSizeGrid: 100,
            thumbnailSizePreview: 1024,
            thumbnailSizeFullSize: 8700,
            thumbnailCostPerPixel: 4,
            thumbnailSizeGridView: 400,
            useThumbnailAsZoomPreview: false,
        )

        // Pass across isolation boundaries
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    // If not truly Sendable, TSan would complain here
                    let copy = settings
                    // Access via MainActor.run: SettingsViewModel is inferred @MainActor,
                    // causing memoryCacheSizeMB to be treated as main-actor-isolated
                    let mb = await MainActor.run { copy.memoryCacheSizeMB }
                    return mb == 5000
                }
            }

            var results: [Bool] = []
            for await result in group {
                results.append(result)
            }

            /*
             #expect(results.allSatisfy(\.self), "All tasks received correct value")
             must be #expect(results.allSatisfy { $0 }, "All tasks received correct value")
             */
            #expect(results.allSatisfy { $0 }, "All tasks received correct value")
        }
    }

    @Test
    func `CacheConfig is truly Sendable`() async {
        let config = CacheConfig(
            totalCostLimit: 1_000_000,
            countLimit: 100,
            costPerPixel: 4,
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    // Pass to actor (crosses isolation boundary)
                    await SharedMemoryCache.shared.ensureReady(config: config)
                }
            }
        }

        #expect(true, "CacheConfig safely crossed isolation boundaries")
    }

    // MARK: - CacheDelegate Data Race Tests

    @Test
    func `CacheDelegate eviction count increment is atomic`() async throws {
        let delegate = CacheDelegate.shared
        await delegate.resetEvictionCount()

        // Create many caches that will evict
        let caches = (0 ..< 100).map { _ in
            NSCache<NSString, DiscardableThumbnail>()
        }

        for cache in caches {
            cache.delegate = delegate
        }

        // Concurrent evictions
        await withTaskGroup(of: Void.self) { group in
            for cache in caches {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 10) {
                        cache.setObject(thumbnail, forKey: "key" as NSString)
                    }
                    cache.removeAllObjects() // Triggers eviction
                }
            }
        }

        try await Task.sleep(for: .milliseconds(100))

        let count = await delegate.getEvictionCount()

        // Count should be consistent (actor ensures atomicity)
        #expect(count >= 0, "Eviction count is never negative")
    }

    // MARK: - Memory Pressure Handler Tests

    @Test
    func `Memory pressure level updates don't race`() async {
        // This tests that writes to currentPressureLevel (from DispatchSource)
        // and reads (from anywhere) don't race

        let cache = SharedMemoryCache.shared

        // Rapid concurrent reads
        await withTaskGroup(of: String.self) { group in
            for _ in 0 ..< 1000 {
                group.addTask {
                    cache.currentPressureLevel.label
                }
            }

            var labels: [String] = []
            for await label in group {
                labels.append(label)
            }

            // All reads should succeed (no TSan errors)
            #expect(labels.allSatisfy { !$0.isEmpty })
        }
    }

    // MARK: - Task Cancellation Safety

    @Test
    func `Cancelled tasks don't leave inconsistent state`() async {
        let cache = SharedMemoryCache.shared

        // Create and immediately cancel many tasks
        let tasks = (0 ..< 100).map { _ in
            Task {
                await cache.ensureReady()
                await cache.updateCacheMemory()
            }
        }

        // Cancel half of them
        for (index, task) in tasks.enumerated() {
            if index % 2 == 0 {
                task.cancel()
            }
        }

        // Wait for all to complete or cancel
        for task in tasks {
            _ = await task.result
        }

        // State should still be consistent
        let stats = await cache.getCacheStatistics()
        #expect(stats.hits >= 0, "State remains consistent after cancellations")
    }

    // MARK: - Stress Tests for TSan

    @Test(
        .timeLimit(.minutes(1)),
        .tags(.performance),
    )
    func `Extreme concurrent load reveals no data races`() async {
        let cache = SharedMemoryCache.shared
        let delegate = CacheDelegate.shared
        let settings = await SettingsViewModel.shared

        // Maximum concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 10000 {
                group.addTask {
                    switch i % 4 {
                    case 0:
                        await cache.ensureReady()

                    case 1:
                        await cache.updateCacheMemory()

                    case 2:
                        _ = await delegate.getEvictionCount()

                    case 3:
                        _ = await settings.asyncgetsettings()

                    default:
                        break
                    }
                }
            }
        }

        #expect(true, "No data races detected under extreme load")
    }
}

// MARK: - Helper Functions

private func createTestThumbnail(size: Int) -> DiscardableThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return DiscardableThumbnail(image: image)
}
