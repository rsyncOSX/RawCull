//
//  ThumbnailProviderTests.swift
//  RawCullTests
//

import AppKit
import Foundation
@testable import RawCull
import Testing

func createTestImage(width: Int = 100, height: Int = 100) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

struct RequestThumbnailTests {
    @Test
    func `new isolated cache starts with empty statistics`() async {
        let cache = await makeIsolatedCache()
        let stats = await cache.getCacheStatistics()

        #expect(stats.hitRate == 0)
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
        #expect(cache.getMemoryCacheCount() == 0)
        #expect(cache.getGridCacheCount() == 0)
    }

    @Test
    func `thumbnail request for missing file returns nil`() async {
        let (provider, cache) = await makeIsolatedThumbnailProvider()
        let missingURL = URL(fileURLWithPath: "/nonexistent/rawcull-\(UUID().uuidString).jpg")

        let result = await provider.requestThumbnail(for: missingURL, targetSize: 256)
        let stats = await cache.getCacheStatistics()

        #expect(result == nil)
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test(.tags(.critical))
    func `cancelled thumbnail request returns nil without surfacing failure`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()
        let missingRaw = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawcull-cancel-\(UUID().uuidString)")
            .appendingPathExtension("arw")

        let result = await withTaskGroup(of: CGImage?.self) { group in
            group.cancelAll()
            group.addTask {
                await provider.requestThumbnail(for: missingRaw, targetSize: 256)
            }
            return await group.next()
        }

        // group.next() returns CGImage?? — task ran in cancelled context and returned nil (inner),
        // so result is .some(nil), not the outer nil. Verify the task completed without surfacing
        // a failure (no crash, no thrown error propagated up).
        #expect(result == .some(nil))
    }

    @Test
    func `clear caches removes cached items and resets statistics`() async {
        let cache = await makeIsolatedCache()
        let key = URL(fileURLWithPath: "/tmp/rawcull-clear-cache.jpg") as NSURL
        let thumbnail = CachedThumbnail(image: createTestImage())

        cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
        cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
        await cache.updateCacheMemory()
        await cache.updateCacheDisk()

        await cache.clearCaches()
        let stats = await cache.getCacheStatistics()

        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
        #expect(cache.getMemoryCacheCount() == 0)
        #expect(cache.getMemoryCacheCurrentCost() == 0)
        #expect(cache.getGridCacheCount() == 0)
        #expect(cache.getGridCacheCurrentCost() == 0)
    }

    @Test
    func `preload nonexistent catalog reports no processed files`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let fakeDir = URL(fileURLWithPath: "/tmp/rawcull-missing-catalog-\(UUID().uuidString)")

        let result = await provider.preloadCatalog(at: fakeDir, targetSize: 256)

        #expect(result == 0)
    }
}

struct CacheConfigTests {
    @Test
    func `production config uses larger limits than testing config`() {
        let production = CacheConfig.production
        let testing = CacheConfig.testing

        #expect(production.totalCostLimit > testing.totalCostLimit)
        #expect(production.countLimit > testing.countLimit)
    }

    @Test
    func `custom config preserves explicit limits`() {
        let config = CacheConfig(
            totalCostLimit: 1_000_000,
            countLimit: 25,
            gridTotalCostLimit: 2_000_000,
        )

        #expect(config.totalCostLimit == 1_000_000)
        #expect(config.countLimit == 25)
        #expect(config.gridTotalCostLimit == 2_000_000)
    }
}

struct CachedThumbnailTests {
    @Test
    func `thumbnail cost is based on pixel footprint`() {
        let image = createTestImage(width: 256, height: 256)
        let thumbnail = CachedThumbnail(image: image)

        #expect(thumbnail.cost >= 256 * 256 * 4)
    }
}
