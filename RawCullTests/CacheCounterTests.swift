import AppKit
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Testing

enum ConcurrencyTests {
    struct SharedMemoryCacheCounterTests {
        @Test(arguments: [false, true])
        func `replacing cache key updates manual counters`(grid: Bool) async throws {
            let cache = await makeIsolatedCache()
            let key = makeThumbnailCacheKey(
                sourceURL: URL(fileURLWithPath: "/tmp/replacement-cache.jpg"),
                purpose: grid ? .grid : .preview,
                requestedPixelSize: 200,
            )
            let first = try #require(createTestThumbnail(size: 10))
            let second = try #require(createTestThumbnail(size: 20))
            if grid {
                cache.setGridObject(first, forKey: key, cost: first.cost)
                cache.setGridObject(second, forKey: key, cost: second.cost)
                #expect(cache.getGridCacheCount() == 1)
                #expect(cache.getGridCacheCurrentCost() == second.cost)
            } else {
                cache.setObject(first, forKey: key, cost: first.cost)
                cache.setObject(second, forKey: key, cost: second.cost)
                #expect(cache.getMemoryCacheCount() == 1)
                #expect(cache.getMemoryCacheCurrentCost() == second.cost)
            }
        }

        @Test
        func `clear caches resets live usage`() async throws {
            let cache = await makeIsolatedCache()
            let key = makeThumbnailCacheKey(
                sourceURL: URL(fileURLWithPath: "/tmp/clear-counters.jpg"),
            )
            let thumbnail = try #require(createTestThumbnail(size: 12))

            cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
            cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
            await cache.clearCaches()

            #expect(cache.getMemoryCacheCount() == 0)
            #expect(cache.getMemoryCacheCurrentCost() == 0)
            #expect(cache.getGridCacheCount() == 0)
            #expect(cache.getGridCacheCurrentCost() == 0)
        }
    }
}

private func createTestThumbnail(size: Int) -> CachedThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return CachedThumbnail(image: image)
}
