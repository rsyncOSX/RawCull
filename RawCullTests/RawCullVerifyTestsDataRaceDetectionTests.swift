//
//  RawCullVerifyTestsDataRaceDetectionTests.swift
//  RawCullVerify
//
//  These tests intentionally exercise isolated cache state from many tasks.
//  They are most valuable when `make test-full` runs with Thread Sanitizer.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

@Suite(.tags(.threadSafety))
struct DataRaceDetectionTests {
    @Test(arguments: [false, true])
    func `cache supports concurrent nonisolated reads and writes`(grid: Bool) async throws {
        let cache = await makeIsolatedCache()
        let thumbnail = try #require(createTestThumbnail(size: 12))
        let keys = (0 ..< 100).map { index in
            makeThumbnailCacheKey(
                sourceURL: URL(fileURLWithPath: "/tmp/rawcull-cache-race-\(index).jpg"),
                purpose: grid ? .grid : .preview,
                requestedPixelSize: 200,
            )
        }
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                group.addTask {
                    if grid {
                        cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
                    } else {
                        cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
                    }
                }
                group.addTask {
                    if grid {
                        _ = cache.gridObject(forKey: key)
                    } else {
                        _ = cache.object(forKey: key)
                    }
                }
            }
        }
        let count = grid ? cache.getGridCacheCount() : cache.getMemoryCacheCount()
        let cost = grid ? cache.getGridCacheCurrentCost() : cache.getMemoryCacheCurrentCost()
        #expect(count > 0)
        #expect(count <= keys.count)
        #expect(cost == count * thumbnail.cost)
    }

    @Test(
        .timeLimit(.minutes(1)),
        .tags(.performance),
    )
    func `Extreme concurrent load reveals no data races`() async throws {
        let cache = await makeIsolatedCache()
        let thumbnail = try #require(createTestThumbnail(size: 12))
        // Bound task creation while contending on both public cache APIs.
        await withTaskGroup(of: Void.self) { group in
            for worker in 0 ..< 16 {
                group.addTask {
                    for iteration in 0 ..< 256 {
                        let key = makeThumbnailCacheKey(
                            sourceURL: URL(fileURLWithPath: "/tmp/stress-\(worker)-\(iteration % 8).jpg"),
                        )
                        cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
                        cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
                        _ = cache.object(forKey: key)
                        _ = cache.gridObject(forKey: key)
                        _ = cache.getMemoryCacheCurrentCost()
                        _ = cache.getGridCacheCount()
                        if iteration.isMultiple(of: 32) {
                            cache.removeAllObjects()
                            cache.removeAllGridObjects()
                        }
                    }
                }
            }
        }
        // After workers drain, counters must agree with the actual live entries.
        let keys = (0 ..< 16).flatMap { worker in
            (0 ..< 8).map { index in
                makeThumbnailCacheKey(sourceURL: URL(fileURLWithPath: "/tmp/stress-\(worker)-\(index).jpg"))
            }
        }
        let memoryCount = keys.filter { cache.object(forKey: $0) != nil }.count
        let gridCount = keys.filter { cache.gridObject(forKey: $0) != nil }.count
        #expect(cache.getMemoryCacheCount() == memoryCount)
        #expect(cache.getMemoryCacheCurrentCost() == memoryCount * thumbnail.cost)
        #expect(cache.getGridCacheCount() == gridCount)
        #expect(cache.getGridCacheCurrentCost() == gridCount * thumbnail.cost)
        await cache.clearCaches()
        #expect(cache.getMemoryCacheCount() == 0)
        #expect(cache.getMemoryCacheCurrentCost() == 0)
        #expect(cache.getGridCacheCount() == 0)
        #expect(cache.getGridCacheCurrentCost() == 0)
    }
}

private func createTestThumbnail(size: Int) -> CachedThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return CachedThumbnail(image: image)
}
