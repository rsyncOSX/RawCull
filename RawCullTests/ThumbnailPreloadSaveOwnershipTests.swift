import AppKit
import Foundation
@testable import RawCull
import Testing

private actor PreloadTestImageLoader: RawImageLoading {
    private(set) var calls = 0

    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? {
        calls += 1
        guard let context = CGContext(
            data: nil,
            width: 32,
            height: 24,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ), let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func thumbnailCGImage(for _: URL, maxPixelSize _: Int) async -> CGImage? {
        nil
    }

    func previewCGImage(for _: URL) async -> CGImage? {
        nil
    }

    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        nil
    }

    func embeddedPreviewJPEGData(for _: URL, matchingPixelWidth _: Int, height _: Int) async -> Data? {
        nil
    }
}

private actor SuspendedPreloadSaves {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var readyWaiter: CheckedContinuation<Void, Never>?
    private var released = false
    private let expected: Int
    private(set) var startedKeys: [ThumbnailCacheKey] = []
    private(set) var finished = 0
    private(set) var gatesReleased = true
    private(set) var preloadReturned = false
    private(set) var peak = 0

    init(expected: Int) {
        self.expected = expected
    }

    func save(_ data: Data, key: ThumbnailCacheKey, diskCache: DiskCacheManager, source: URL) async {
        // This must complete before the stalled write is released.
        let available = await ThumbnailPreloadGate.shared.waitUntilGridDecodeIsAvailable(for: source)
        gatesReleased = gatesReleased && available
        startedKeys.append(key)
        if !released {
            await withCheckedContinuation { continuation in
                held.append(continuation)
                peak = max(peak, held.count)
                if held.count == expected {
                    readyWaiter?.resume()
                    readyWaiter = nil
                }
            }
        }
        await diskCache.save(data, for: key)
        finished += 1
    }

    func waitUntilFull() async {
        if held.count >= expected {
            return
        }
        await withCheckedContinuation { readyWaiter = $0 }
    }

    func markPreloadReturned() {
        preloadReturned = true
    }

    func release() {
        released = true
        let continuations = held
        held.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }
}

struct ThumbnailPreloadSaveOwnershipTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func `preload owns bounded saves and releases gates before disk completion`(cancel: Bool) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreloadSaveOwnership-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("Catalog", isDirectory: true)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        let limit = RawImageLoadingConcurrency.thumbnailPreloadLimit
        let sources = (0 ..< limit * 2 + 1).map { catalog.appendingPathComponent("\($0).ARW") }
        for source in sources {
            try Data().write(to: source)
        }
        let disk = DiskCacheManager(cacheDirectory: root.appendingPathComponent("Cache"))
        let loader = PreloadTestImageLoader()
        let saves = SuspendedPreloadSaves(expected: limit)
        // Resolve keys up front so the saver can verify the corresponding grid gate.
        var sourceByKey: [ThumbnailCacheKey: URL] = [:]
        for source in sources {
            try sourceByKey[#require(ThumbnailCacheKey.resolve(
                for: source, purpose: .preview, requestedPixelSize: 256,
            ))] = source
        }
        let resolvedSources = sourceByKey
        let provider = ScanAndCreateThumbnails(diskCache: disk, rawLoader: loader, saveToDisk: { data, key in
            guard let source = resolvedSources[key] else {
                Issue.record("Unexpected cache key")
                return
            }
            await saves.save(data, key: key, diskCache: disk, source: source)
        })
        let preload = Task {
            let count = await provider.preloadCatalog(at: catalog, targetSize: 256)
            await saves.markPreloadReturned()
            return count
        }
        await saves.waitUntilFull()
        // Give incorrectly detached work an opportunity to run beyond the bound.
        for _ in 0 ..< 100 {
            await Task.yield()
        }
        #expect(await loader.calls == limit)
        #expect(await saves.startedKeys.count == limit)
        #expect(await saves.gatesReleased)
        #expect(await saves.finished == 0)
        #expect(await !saves.preloadReturned)
        for key in await saves.startedKeys {
            #expect(SharedMemoryCache.shared.object(forKey: key) == nil)
            let gridKey = try #require(key.representation(purpose: .grid, requestedPixelSize: 200))
            #expect(SharedMemoryCache.shared.gridObject(forKey: gridKey) != nil)
        }
        if cancel {
            await provider.cancelPreload()
        }
        await saves.release()
        let processed = await preload.value
        let expectedCount = cancel ? limit : sources.count
        #expect(processed == expectedCount)
        let progress = await provider.progressCounts()
        #expect(progress.completed == expectedCount)
        #expect(progress.total == sources.count)
        #expect(await loader.calls == expectedCount)
        #expect(await saves.finished == expectedCount)
        #expect(await saves.peak <= limit)
        for key in await saves.startedKeys {
            let cached = await disk.load(for: key)
            #expect(cancel ? cached == nil : cached != nil)
        }
        if !cancel {
            let warmProcessed = await provider.preloadCatalog(at: catalog, targetSize: 256)
            #expect(warmProcessed == sources.count)
            #expect(await loader.calls == sources.count)
            #expect(await saves.startedKeys.count == sources.count)
        }
        // Session teardown must release even the undiscovered files on cancellation.
        for source in sources {
            #expect(await ThumbnailPreloadGate.shared.waitUntilGridDecodeIsAvailable(for: source))
        }
    }
}
