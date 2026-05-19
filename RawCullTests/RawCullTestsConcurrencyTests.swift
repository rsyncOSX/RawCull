//
//  RawCullTestsConcurrencyTests.swift
//  RawCull
//

import AppKit
import Foundation
@testable import RawCull
import Testing

enum ConcurrencyTests {
    struct SharedMemoryCacheCounterTests {
        @Test
        func `replacing memory cache key updates manual counters`() async throws {
            let cache = await makeIsolatedCache()
            cache.removeAllObjects()
            defer { cache.removeAllObjects() }

            let key = URL(fileURLWithPath: "/tmp/replacement-main-cache.jpg") as NSURL
            let first = try #require(createTestThumbnail(size: 10))
            let second = try #require(createTestThumbnail(size: 20))

            cache.setObject(first, forKey: key, cost: first.cost)
            cache.setObject(second, forKey: key, cost: second.cost)

            #expect(cache.getMemoryCacheCount() == 1)
            #expect(cache.getMemoryCacheCurrentCost() == second.cost)
        }

        @Test
        func `replacing grid cache key updates manual counters`() async throws {
            let cache = await makeIsolatedCache()
            cache.removeAllGridObjects()
            defer { cache.removeAllGridObjects() }

            let key = URL(fileURLWithPath: "/tmp/replacement-grid-cache.jpg") as NSURL
            let first = try #require(createTestThumbnail(size: 10))
            let second = try #require(createTestThumbnail(size: 20))

            cache.setGridObject(first, forKey: key, cost: first.cost)
            cache.setGridObject(second, forKey: key, cost: second.cost)

            #expect(cache.getGridCacheCount() == 1)
            #expect(cache.getGridCacheCurrentCost() == second.cost)
        }

        @Test
        func `cache statistics reflect recorded memory and disk hits`() async {
            let cache = await makeIsolatedCache()

            await cache.updateCacheMemory()
            await cache.updateCacheMemory()
            await cache.updateCacheDisk()

            let stats = await cache.getCacheStatistics()
            #expect(stats.hits == 2)
            #expect(stats.misses == 1)
            #expect(stats.hitRate == (2.0 / 3.0 * 100.0))
        }

        @Test
        func `clear caches resets live counters and diagnostics`() async throws {
            let cache = await makeIsolatedCache()
            let key = URL(fileURLWithPath: "/tmp/clear-counters.jpg") as NSURL
            let thumbnail = try #require(createTestThumbnail(size: 12))

            cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
            cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
            await cache.updateCacheMemory()
            await cache.updateCacheDisk()
            cache.incrementColdExtract()
            cache.incrementDemandRequest()
            cache.incrementBoomerangMiss()
            cache.noteEviction(url: key)

            await cache.clearCaches()
            let stats = await cache.getCacheStatistics()

            #expect(cache.getMemoryCacheCount() == 0)
            #expect(cache.getMemoryCacheCurrentCost() == 0)
            #expect(cache.getGridCacheCount() == 0)
            #expect(cache.getGridCacheCurrentCost() == 0)
            #expect(stats.hits == 0)
            #expect(stats.misses == 0)
            #expect(cache.getColdExtractCount() == 0)
            #expect(cache.getDemandRequestCount() == 0)
            #expect(cache.getBoomerangMissCount() == 0)
            #expect(!cache.wasRecentlyEvicted(url: key))
        }
    }

    struct SettingsViewModelPersistenceTests {
        @Test
        func `settings save and load round trips through isolated file`() async {
            let viewModel = await makeIsolatedSettingsViewModel()

            await MainActor.run {
                viewModel.memoryCacheSizeMB = 1000
                viewModel.gridCacheSizeMB = 1500
                viewModel.thumbnailSizeGrid = 200
            }

            await viewModel.saveSettings()

            await MainActor.run {
                viewModel.memoryCacheSizeMB = 2000
                viewModel.gridCacheSizeMB = 400
                viewModel.thumbnailSizeGrid = 300
            }

            await viewModel.loadSettings()
            let savedSettings = await viewModel.asyncgetsettings()
            let savedMB = await MainActor.run { savedSettings.memoryCacheSizeMB }
            let savedGridCache = await MainActor.run { savedSettings.gridCacheSizeMB }
            let savedGrid = await MainActor.run { savedSettings.thumbnailSizeGrid }

            #expect(savedMB == 1000)
            #expect(savedGridCache == 1500)
            #expect(savedGrid == 200)
        }

        @Test
        func `save during initial load preserves persisted grid cache size`() async throws {
            let url = makeIsolatedSettingsURL()
            let data = Data("""
            {
              "gridCacheSizeMB" : 1750,
              "memoryCacheSizeMB" : 7000,
              "thumbnailSizeFullSize" : 8700,
              "thumbnailSizeGrid" : 240,
              "thumbnailSizePreview" : 1664
            }
            """.utf8)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try data.write(to: url, options: .atomic)

            let viewModel = await MainActor.run {
                SettingsViewModel(settingsFileURL: url, loadOnInit: true)
            }

            await viewModel.saveSettings()
            await viewModel.loadSettings()
            let savedSettings = await viewModel.asyncgetsettings()
            let savedGridCache = await MainActor.run { savedSettings.gridCacheSizeMB }

            #expect(savedGridCache == 1750)
        }

        @Test
        func `asyncgetsettings returns value snapshot`() async {
            let viewModel = await makeIsolatedSettingsViewModel()

            await MainActor.run {
                viewModel.memoryCacheSizeMB = 5000
            }
            let snapshot = await viewModel.asyncgetsettings()

            await MainActor.run {
                viewModel.memoryCacheSizeMB = 9999
            }
            let snapshotMB = await MainActor.run { snapshot.memoryCacheSizeMB }

            #expect(snapshotMB == 5000)
        }
    }

    struct MemoryViewModelTests {
        @Test
        func `memory stats update populates coherent values`() async {
            let viewModel = await MemoryViewModel()

            await viewModel.updateMemoryStats()

            let totalMemory = await viewModel.totalMemory
            let usedMemory = await viewModel.usedMemory
            let appMemory = await viewModel.appMemory

            #expect(totalMemory > 0)
            #expect(usedMemory > 0)
            #expect(appMemory > 0)
            #expect(usedMemory <= totalMemory)
            #expect(appMemory <= usedMemory)
        }
    }
}

private func createTestThumbnail(size: Int) -> CachedThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return CachedThumbnail(image: image)
}

extension Tag {
    @Tag static var critical: Self
    @Tag static var performance: Self
    @Tag static var threadSafety: Self
    @Tag static var smoke: Self
}
