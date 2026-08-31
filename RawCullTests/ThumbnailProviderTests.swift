//
//  ThumbnailProviderTests.swift
//  RawCullVerifyTests
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
    func `new isolated cache starts empty`() async {
        let cache = await makeIsolatedCache()

        #expect(cache.getMemoryCacheCount() == 0)
        #expect(cache.getGridCacheCount() == 0)
    }

    @Test
    func `thumbnail request for missing file returns nil`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()
        let missingURL = URL(fileURLWithPath: "/nonexistent/rawcull-\(UUID().uuidString).jpg")

        let result = await provider.requestThumbnail(
            for: missingURL,
            targetSize: 256,
            purpose: .preview,
        )
        #expect(result == nil)
    }

    @Test(.tags(.critical))
    func `cancelled thumbnail request returns nil without surfacing failure`() async {
        let (provider, _) = await makeIsolatedThumbnailProvider()
        let missingRaw = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rawcull-cancel-\(UUID().uuidString)")
            .appendingPathExtension("arw")

        // group.next() returns CGImage??; unwrap only the outer "next result" optional.
        let result: CGImage? = await withTaskGroup(of: CGImage?.self) { group in
            group.cancelAll()
            group.addTask {
                await provider.requestThumbnail(
                    for: missingRaw,
                    targetSize: 256,
                    purpose: .preview,
                )
            }
            guard let result = await group.next() else {
                return nil
            }
            return result
        }

        #expect(result == nil)
    }

    @Test
    func `clear caches removes cached items`() async {
        let cache = await makeIsolatedCache()
        let key = makeThumbnailCacheKey(
            sourceURL: URL(fileURLWithPath: "/tmp/rawcull-clear-cache.jpg"),
        )
        let thumbnail = CachedThumbnail(image: createTestImage())

        cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
        cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
        await cache.clearCaches()

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
    private let mb = CacheRecommendationPolicy.megabyte

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

    @Test
    func `sixteen GB low free memory keeps adaptive baseline`() {
        let physical = UInt64(16 * 1024 * mb)
        let used = UInt64(13 * 1024 * mb)

        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            userPreviewMaxMB: 4096,
            userGridMaxMB: 1024,
            pressureLevel: .normal,
        )

        #expect(limits.previewMB == 2048)
        #expect(limits.gridMB == 768)
    }

    @Test
    func `sixteen GB with five point six GB free prioritizes grid cache`() {
        let physical = UInt64(16 * 1024 * mb)
        let used = UInt64((16 * 1024 - 5734) * mb)

        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            userPreviewMaxMB: 4096,
            userGridMaxMB: 1024,
            pressureLevel: .normal,
        )

        #expect(limits.previewMB == 3072)
        #expect(limits.gridMB == 1024)
    }

    @Test
    func `sixteen GB high free memory caps at safe tier`() {
        let physical = UInt64(16 * 1024 * mb)
        let used = UInt64(6 * 1024 * mb)

        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            userPreviewMaxMB: 8000,
            userGridMaxMB: 2000,
            pressureLevel: .normal,
        )

        #expect(limits.previewMB == 4096)
        #expect(limits.gridMB == 1024)
    }

    @Test
    func `adaptive cache respects user maximums`() {
        let physical = UInt64(16 * 1024 * mb)
        let used = UInt64(8 * 1024 * mb)

        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            userPreviewMaxMB: 2500,
            userGridMaxMB: 900,
            pressureLevel: .normal,
        )

        #expect(limits.previewMB == 2500)
        #expect(limits.gridMB == 900)
    }

    @Test
    func `warning pressure shrinks adaptive baseline`() {
        let physical = UInt64(16 * 1024 * mb)
        let used = UInt64(8 * 1024 * mb)

        let limits = CacheRecommendationPolicy.adaptiveLimits(
            physicalMemoryBytes: physical,
            usedMemoryBytes: used,
            userPreviewMaxMB: 4096,
            userGridMaxMB: 1024,
            pressureLevel: .warning,
        )

        #expect(limits.previewMB == 1280)
        #expect(limits.gridMB == 512)
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
