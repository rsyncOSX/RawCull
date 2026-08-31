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
    func `memory cache supports concurrent nonisolated reads and writes`() async {
        let cache = await makeIsolatedCache()
        let keys = (0 ..< 100).map { index in
            makeThumbnailCacheKey(
                sourceURL: URL(fileURLWithPath: "/tmp/rawcull-cache-race-\(index).jpg"),
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 10 + index % 5) {
                        cache.setObject(thumbnail, forKey: key, cost: thumbnail.cost)
                    }
                }
                group.addTask {
                    _ = cache.object(forKey: key)
                }
            }
        }

        let count = cache.getMemoryCacheCount()
        let cost = cache.getMemoryCacheCurrentCost()
        #expect(count >= 0)
        #expect(count <= keys.count)
        #expect(cost >= 0)
    }

    @Test
    func `grid cache supports concurrent nonisolated reads and writes`() async {
        let cache = await makeIsolatedCache()
        let keys = (0 ..< 100).map { index in
            makeThumbnailCacheKey(
                sourceURL: URL(fileURLWithPath: "/tmp/rawcull-grid-race-\(index).jpg"),
                purpose: .grid,
                requestedPixelSize: 200,
            )
        }

        await withTaskGroup(of: Void.self) { group in
            for (index, key) in keys.enumerated() {
                group.addTask {
                    if let thumbnail = createTestThumbnail(size: 8 + index % 5) {
                        cache.setGridObject(thumbnail, forKey: key, cost: thumbnail.cost)
                    }
                }
                group.addTask {
                    _ = cache.gridObject(forKey: key)
                }
            }
        }

        let count = cache.getGridCacheCount()
        let cost = cache.getGridCacheCurrentCost()
        #expect(count >= 0)
        #expect(count <= keys.count)
        #expect(cost >= 0)
    }

    @Test(
        .timeLimit(.minutes(1)),
        .tags(.performance),
    )
    func `Extreme concurrent load reveals no data races`() async {
        let cache = await makeIsolatedCache()
        let settings = await makeIsolatedSettingsViewModel()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 10000 {
                group.addTask {
                    switch index % 4 {
                    case 0:
                        await cache.ensureReady()

                    case 1:
                        _ = cache.getMemoryCacheCount()

                    case 2:
                        _ = cache.getGridCacheCurrentCost()

                    default:
                        _ = await settings.asyncgetsettings()
                    }
                }
            }
        }

        #expect(cache.getMemoryCacheCount() >= 0)
    }
}

private func createTestThumbnail(size: Int) -> CachedThumbnail? {
    let image = NSImage(size: NSSize(width: size, height: size))
    return CachedThumbnail(image: image)
}
