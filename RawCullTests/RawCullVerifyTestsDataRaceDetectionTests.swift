//
//  RawCullVerifyTestsDataRaceDetectionTests.swift
//  RawCullVerify
//
//  These tests intentionally exercise RawCullVerify shared state from many tasks.
//  They are most valuable when `make test-full` runs with Thread Sanitizer.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

@Suite(.tags(.threadSafety))
struct DataRaceDetectionTests {
    @Test
    func `pressure level can be sampled concurrently`() async {
        let cache = SharedMemoryCache.shared

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

            #expect(labels.count == 1000)
            #expect(labels.allSatisfy { !$0.isEmpty })
        }
    }

    @Test
    func `memory cache supports concurrent nonisolated reads and writes`() async {
        let cache = await makeIsolatedCache()
        let urls = (0 ..< 100).map { index in
            URL(fileURLWithPath: "/tmp/rawcull-cache-race-\(index).jpg") as NSURL
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 10 + index % 5) {
                        cache.setObject(thumbnail, forKey: url, cost: thumbnail.cost)
                    }
                }
                group.addTask {
                    _ = cache.object(forKey: url)
                }
            }
        }

        let count = cache.getMemoryCacheCount()
        let cost = cache.getMemoryCacheCurrentCost()
        #expect(count >= 0)
        #expect(count <= urls.count)
        #expect(cost >= 0)
    }

    @Test
    func `grid cache supports concurrent nonisolated reads and writes`() async {
        let cache = await makeIsolatedCache()
        let urls = (0 ..< 100).map { index in
            URL(fileURLWithPath: "/tmp/rawcull-grid-race-\(index).jpg") as NSURL
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 8 + index % 5) {
                        cache.setGridObject(thumbnail, forKey: url, cost: thumbnail.cost)
                    }
                }
                group.addTask {
                    _ = cache.gridObject(forKey: url)
                }
            }
        }

        let count = cache.getGridCacheCount()
        let cost = cache.getGridCacheCurrentCost()
        #expect(count >= 0)
        #expect(count <= urls.count)
        #expect(cost >= 0)
    }

    @Test
    func `cache diagnostic counters remain coherent under concurrent increments`() async {
        let cache = await makeIsolatedCache()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 300 {
                group.addTask {
                    switch index % 3 {
                    case 0:
                        cache.incrementColdExtract()

                    case 1:
                        cache.incrementDemandRequest()

                    default:
                        cache.incrementBoomerangMiss()
                    }
                }
            }
        }

        #expect(cache.getColdExtractCount() == 100)
        #expect(cache.getDemandRequestCount() == 100)
        #expect(cache.getBoomerangMissCount() == 100)
    }

    @Test(
        .timeLimit(.minutes(1)),
        .tags(.performance),
    )
    func `Extreme concurrent load reveals no data races`() async {
        let cache = await makeIsolatedCache()
        let delegate = CacheDelegate.shared
        let settings = await makeIsolatedSettingsViewModel()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 10000 {
                group.addTask {
                    switch index % 4 {
                    case 0:
                        await cache.ensureReady()

                    case 1:
                        await cache.updateCacheMemory()

                    case 2:
                        _ = delegate.getEvictionCount()

                    default:
                        _ = await settings.asyncgetsettings()
                    }
                }
            }
        }

        let stats = await cache.getCacheStatistics()
        #expect(stats.hits == 2500)
        #expect(stats.misses == 0)
    }
}

private func createTestThumbnail(size: Int) -> CachedThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return CachedThumbnail(image: image)
}
