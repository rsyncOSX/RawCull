import AppKit
import Foundation
@testable import RawCull
import Testing

struct CacheAccountingConcurrencyTests {
    @Test(arguments: [false, true])
    func `Concurrent replacements count one live entry`(grid: Bool) async throws {
        let owner = await makeIsolatedCache()
        let cache = grid ? owner.gridThumbnailCache : owner.memoryCache
        let key = "one-key"
        let first = try #require(accountingThumbnail(size: 10))
        let second = try #require(accountingThumbnail(size: 20))
        await withTaskGroup(of: Void.self) { group in
            for worker in 0 ..< 16 {
                group.addTask {
                    for iteration in 0 ..< 200 {
                        let image = (worker + iteration).isMultiple(of: 2) ? first : second
                        cache.setObject(image, forKey: key as NSString, cost: image.cost)
                    }
                }
            }
        }
        let live = try #require(cache.object(forKey: key as NSString))
        #expect(cache.currentCount == 1)
        #expect(cache.currentCost == live.cost)
    }

    @Test(arguments: [false, true])
    func `Concurrent clear and insert leave consistent accounting`(grid: Bool) async throws {
        let owner = await makeIsolatedCache()
        let cache = grid ? owner.gridThumbnailCache : owner.memoryCache
        let image = try #require(accountingThumbnail(size: 10))
        await withTaskGroup(of: Void.self) { group in
            for worker in 0 ..< 12 {
                group.addTask {
                    for iteration in 0 ..< 200 {
                        if (worker + iteration).isMultiple(of: 3) {
                            cache.removeAllObjects()
                        } else {
                            cache.setObject(image, forKey: "key", cost: image.cost)
                        }
                    }
                }
            }
        }
        let hasEntry = cache.object(forKey: "key") != nil
        #expect(cache.currentCount == (hasEntry ? 1 : 0))
        #expect(cache.currentCost == (hasEntry ? image.cost : 0))
        cache.removeAllObjects()
        #expect(cache.currentCount == 0)
        #expect(cache.currentCost == 0)
        cache.setObject(image, forKey: "key", cost: image.cost)
        #expect(cache.currentCount == 1)
        #expect(cache.currentCost == image.cost)
    }

    @Test(arguments: [false, true])
    func `Evictions update the owning cache rather than the singleton`(grid: Bool) async throws {
        let owner = await makeIsolatedCache()
        let cache = grid ? owner.gridThumbnailCache : owner.memoryCache
        cache.countLimit = 2
        let image = try #require(accountingThumbnail(size: 10))
        let keys = (0 ..< 50).map { "entry-\($0)" as NSString }
        for key in keys {
            cache.setObject(image, forKey: key, cost: image.cost)
        }
        let liveCount = keys.filter { cache.object(forKey: $0) != nil }.count
        #expect(cache.currentCount == liveCount)
        #expect(cache.currentCost == liveCount * image.cost)
        cache.totalCostLimit = 1
        let remaining = keys.filter { cache.object(forKey: $0) != nil }.count
        #expect(cache.currentCount == remaining)
        #expect(cache.currentCost == remaining * image.cost)
    }
}

private func accountingThumbnail(size: Int) -> CachedThumbnail? {
    guard let image = CGContext(data: nil, width: size, height: size,
                                bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return nil }
    return CachedThumbnail(image: NSImage(cgImage: image, size: NSSize(width: size, height: size)))
}
