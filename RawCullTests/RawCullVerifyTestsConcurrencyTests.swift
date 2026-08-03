//
//  RawCullVerifyTestsConcurrencyTests.swift
//  RawCullVerify
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

            let key = makeThumbnailRequestKey(url: URL(fileURLWithPath: "/tmp/replacement-main-cache.jpg"))
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

            let key = makeThumbnailRequestKey(
                url: URL(fileURLWithPath: "/tmp/replacement-grid-cache.jpg"),
                purpose: .grid,
                requestedMaxPixelSize: 200,
            )
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
            let key = makeThumbnailRequestKey(url: URL(fileURLWithPath: "/tmp/clear-counters.jpg"))
            let thumbnail = try #require(createTestThumbnail(size: 12))

            cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
            cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
            await cache.updateCacheMemory()
            await cache.updateCacheDisk()
            cache.incrementColdExtract()
            cache.incrementDemandRequest()
            cache.incrementBoomerangMiss()
            cache.noteEviction(key: key)

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
            #expect(!cache.wasRecentlyEvicted(key: key))
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
                viewModel.scoringPhotoType = .portrait
                viewModel.scoringQuality = .highPrecision
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
            let savedPhotoType = await MainActor.run { savedSettings.scoringPhotoType }
            let savedQuality = await MainActor.run { savedSettings.scoringQuality }

            #expect(savedMB == 1000)
            #expect(savedGridCache == 1500)
            #expect(savedGrid == 200)
            #expect(savedPhotoType == .portrait)
            #expect(savedQuality == .highPrecision)
        }

        @Test
        func `save during initial load preserves persisted cache maximums`() async throws {
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
        @MainActor
        func `legacy settings JSON defaults scoring photo type to auto and ignores badge toggles`() throws {
            let data = Data("""
            {
              "gridCacheSizeMB" : 1750,
              "memoryCacheSizeMB" : 7000,
              "showSaliencyBadge" : true,
              "showScoringBadge" : true,
              "thumbnailSizeFullSize" : 8700,
              "thumbnailSizeGrid" : 240,
              "thumbnailSizePreview" : 1664
            }
            """.utf8)

            let settings = try JSONDecoder().decode(SavedSettings.self, from: data)

            #expect(settings.scoringPhotoType == .auto)
            #expect(settings.scoringQuality == .fast)
        }

        @Test
        @MainActor
        func `extreme settings JSON decodes inside supported ranges`() throws {
            let data = Data("""
            {
              "focusMaskDilationRadius" : 99,
              "focusMaskEnergyMultiplier" : 99,
              "focusMaskErosionRadius" : -1,
              "focusMaskFeatherRadius" : -5,
              "focusMaskPreBlurRadius" : 99,
              "focusMaskThreshold" : 9,
              "gridCacheSizeMB" : 99,
              "memoryCacheSizeMB" : 99999,
              "scoringBorderInsetFraction" : 9,
              "scoringSalientWeight" : 9,
              "scoringSubjectSizeFactor" : 9,
              "scoringThumbnailMaxPixelSize" : -1,
              "thumbnailSharpenAmount" : 99,
              "thumbnailSizeFullSize" : -1,
              "thumbnailSizeGrid" : 999,
              "thumbnailSizePreview" : 99
            }
            """.utf8)

            let settings = try JSONDecoder().decode(SavedSettings.self, from: data)

            #expect(settings.memoryCacheSizeMB == 8000)
            #expect(settings.gridCacheSizeMB == 400)
            #expect(settings.thumbnailSizeGrid == 300)
            #expect(settings.thumbnailSizePreview == 1024)
            #expect(settings.thumbnailSizeFullSize == 8700)
            #expect(settings.thumbnailSharpenAmount == 2.0)
            #expect(settings.scoringBorderInsetFraction == 0.10)
            #expect(settings.scoringSalientWeight == 1.0)
            #expect(settings.scoringSubjectSizeFactor == 3.0)
            #expect(settings.scoringThumbnailMaxPixelSize == 2048)
            #expect(settings.focusMaskPreBlurRadius == 4.0)
            #expect(settings.focusMaskThreshold == 0.70)
            #expect(settings.focusMaskEnergyMultiplier == 20.0)
            #expect(settings.focusMaskErosionRadius == 0.0)
            #expect(settings.focusMaskDilationRadius == 3.0)
            #expect(settings.focusMaskFeatherRadius == 0.0)
        }

        @Test
        @MainActor
        func `save writes normalized settings`() async throws {
            let url = makeIsolatedSettingsURL()
            let root = url.deletingLastPathComponent()
            defer { try? FileManager.default.removeItem(at: root) }
            let viewModel = SettingsViewModel(settingsFileURL: url, loadOnInit: false)

            viewModel.memoryCacheSizeMB = 42
            viewModel.gridCacheSizeMB = 99999
            viewModel.thumbnailSizeGrid = 1
            viewModel.thumbnailSizePreview = 99999
            viewModel.thumbnailSizeFullSize = -1
            viewModel.thumbnailSharpenAmount = 99
            viewModel.scoringSalientWeight = 99
            viewModel.focusMaskThreshold = -1

            await viewModel.saveSettings()

            let data = try Data(contentsOf: url)
            let saved = try JSONDecoder().decode(SavedSettings.self, from: data)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

            #expect(saved.memoryCacheSizeMB == 1000)
            #expect(saved.gridCacheSizeMB == 2000)
            #expect(saved.thumbnailSizeGrid == 100)
            #expect(saved.thumbnailSizePreview == 1664)
            #expect(saved.thumbnailSizeFullSize == 8700)
            #expect(saved.thumbnailSharpenAmount == 2.0)
            #expect(saved.scoringSalientWeight == 1.0)
            #expect(saved.focusMaskThreshold == 0.01)
            #expect(json["showScoringBadge"] == nil)
            #expect(json["showSaliencyBadge"] == nil)
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

        @Test
        @MainActor
        func `asyncgetsettings returns normalized value snapshot`() async {
            let viewModel = makeIsolatedSettingsViewModel()

            viewModel.memoryCacheSizeMB = 42
            viewModel.gridCacheSizeMB = 99999
            viewModel.thumbnailSharpenAmount = -1
            viewModel.scoringSubjectSizeFactor = 99

            let snapshot = await viewModel.asyncgetsettings()

            #expect(snapshot.memoryCacheSizeMB == 1000)
            #expect(snapshot.gridCacheSizeMB == 2000)
            #expect(snapshot.thumbnailSharpenAmount == 0.0)
            #expect(snapshot.scoringSubjectSizeFactor == 3.0)
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
