import AppKit
import Foundation
@testable import RawCull
import Testing

private actor ContendedThumbnailImageLoader: RawImageLoading {
    private let image: CGImage
    private var callCount = 0
    private var waiters: [UUID: CheckedContinuation<CGImage?, Never>] = [:]

    init(image: CGImage) {
        self.image = image
    }

    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        nil
    }

    func thumbnailCGImage(for _: URL, maxPixelSize _: Int) async -> CGImage? {
        callCount += 1
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancel(id: id)
            }
        }
    }

    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? {
        nil
    }

    func previewCGImage(for _: URL) async -> CGImage? {
        nil
    }

    func releaseAll() {
        let continuations = waiters.values
        waiters.removeAll()
        for continuation in continuations {
            continuation.resume(returning: image)
        }
    }

    func snapshot() -> (calls: Int, waiters: Int) {
        (callCount, waiters.count)
    }

    private func cancel(id: UUID) {
        waiters.removeValue(forKey: id)?.resume(returning: nil)
    }
}

private struct ThumbnailContentionFixture {
    let root: URL
    let sourceURL: URL
    let provider: RequestThumbnail
    let loader: ContendedThumbnailImageLoader
    let diagnostics: ContentionDiagnostics
}

@Suite("Thumbnail contention", .serialized)
struct ThumbnailContentionTests {
    @Test(
        arguments: [12, 120, 1200],
    )
    func `fixed catalog duplicate profiles coalesce one exact key`(requestCount: Int) async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let requests = Task {
            await withTaskGroup(of: CGImage?.self, returning: [CGImage?].self) { group in
                for _ in 0 ..< requestCount {
                    group.addTask {
                        await fixture.provider.requestThumbnail(
                            for: fixture.sourceURL,
                            targetSize: 512,
                            purpose: .preview,
                        )
                    }
                }

                var results: [CGImage?] = []
                results.reserveCapacity(requestCount)
                for await result in group {
                    results.append(result)
                }
                return results
            }
        }

        try await waitUntil {
            let loaderSnapshot = await fixture.loader.snapshot()
            return fixture.diagnostics.snapshot().coalescedThumbnailWaiters
                == requestCount - 1
                && loaderSnapshot.calls == 1
                && loaderSnapshot.waiters == 1
        }
        #expect(await fixture.loader.snapshot().calls == 1)

        await fixture.loader.releaseAll()
        let results = await requests.value
        let snapshot = fixture.diagnostics.snapshot()

        #expect(results.count == requestCount)
        #expect(results.allSatisfy { $0 != nil })
        #expect(snapshot.coldThumbnailDecodes == 1)
        #expect(snapshot.duplicateThumbnailKeys == requestCount - 1)
        #expect(snapshot.coalescedThumbnailWaiters == requestCount - 1)
        #expect(snapshot.activeThumbnailWork == 0)
        #expect(snapshot.peakThumbnailWork == 1)
        #expect(await fixture.provider.inFlightSnapshotForTesting().requests == 0)
        #expect(await fixture.provider.inFlightSnapshotForTesting().waiters == 0)
    }

    @Test
    func `cancelling one waiter preserves the shared producer`() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let first = Task {
            await fixture.provider.requestThumbnail(
                for: fixture.sourceURL,
                targetSize: 512,
                purpose: .preview,
            )
        }
        let second = Task {
            await fixture.provider.requestThumbnail(
                for: fixture.sourceURL,
                targetSize: 512,
                purpose: .preview,
            )
        }

        try await waitUntil {
            fixture.diagnostics.snapshot().coalescedThumbnailWaiters == 1
        }
        second.cancel()
        #expect(await second.value == nil)
        #expect(await fixture.loader.snapshot().calls == 1)
        #expect(await fixture.loader.snapshot().waiters == 1)

        await fixture.loader.releaseAll()
        #expect(await first.value != nil)

        let snapshot = fixture.diagnostics.snapshot()
        #expect(snapshot.thumbnailCancellations == 1)
        #expect(snapshot.activeThumbnailWork == 0)
        #expect(await fixture.provider.inFlightSnapshotForTesting().requests == 0)
        #expect(await fixture.provider.inFlightSnapshotForTesting().waiters == 0)
    }

    @Test
    func `cancelling the final waiter cancels the producer without a leak`() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let request = Task {
            await fixture.provider.requestThumbnail(
                for: fixture.sourceURL,
                targetSize: 512,
                purpose: .preview,
            )
        }
        try await waitUntil { await fixture.loader.snapshot().waiters == 1 }

        request.cancel()
        #expect(await request.value == nil)
        try await waitUntil { await fixture.loader.snapshot().waiters == 0 }
        try await waitUntil {
            fixture.diagnostics.snapshot().activeThumbnailWork == 0
        }

        let snapshot = fixture.diagnostics.snapshot()
        #expect(snapshot.thumbnailCancellations == 1)
        #expect(snapshot.activeThumbnailWork == 0)
        #expect(await fixture.provider.inFlightSnapshotForTesting().requests == 0)
        #expect(await fixture.provider.inFlightSnapshotForTesting().waiters == 0)
    }

    @Test
    func `grid gate blocks only the active catalog and drains cancellation`() async throws {
        let gate = ThumbnailPreloadGate()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let catalog = root.appendingPathComponent("selected", isDirectory: true)
        let otherCatalog = root.appendingPathComponent("other", isDirectory: true)
        let gateID = await gate.begin(catalogURL: catalog)

        let blocked = Task {
            await gate.waitUntilGridDecodeIsAvailable(
                for: catalog.appendingPathComponent("blocked.arw"),
            )
        }
        try await waitUntil { await gate.snapshotForTesting().waiters == 1 }

        let unrelated = await gate.waitUntilGridDecodeIsAvailable(
            for: otherCatalog.appendingPathComponent("free.arw"),
        )
        #expect(unrelated)

        blocked.cancel()
        #expect(await blocked.value == false)
        try await waitUntil { await gate.snapshotForTesting().waiters == 0 }
        await gate.end(gateID)
        #expect(await gate.snapshotForTesting().activeCatalogs == 0)
    }

    @Test
    func `ending grid preload resumes every eligible waiter`() async throws {
        let gate = ThumbnailPreloadGate()
        let catalog = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let gateID = await gate.begin(catalogURL: catalog)
        let waiters = (0 ..< 20).map { index in
            Task {
                await gate.waitUntilGridDecodeIsAvailable(
                    for: catalog.appendingPathComponent("\(index).arw"),
                )
            }
        }
        try await waitUntil { await gate.snapshotForTesting().waiters == 20 }

        await gate.end(gateID)
        for waiter in waiters {
            #expect(await waiter.value)
        }
        let snapshot = await gate.snapshotForTesting()
        #expect(snapshot.activeCatalogs == 0)
        #expect(snapshot.waiters == 0)
    }

    @Test @MainActor
    func `contention diagnostics expose independent thumbnail and AI counters`() {
        let diagnostics = ContentionDiagnostics()
        diagnostics.beginThumbnailWork(coldDecode: true)
        diagnostics.beginThumbnailWork(coldDecode: true)
        diagnostics.recordDuplicateThumbnailKey()
        diagnostics.recordThumbnailCancellation()
        diagnostics.recordInferenceStart(.similarityIndexing)
        diagnostics.recordInferenceStart(.semanticSearch)
        diagnostics.recordInferenceStart(.deepReview)
        diagnostics.recordSemanticHydrationStart()
        diagnostics.recordModelDownloadStart()
        let preloadID = diagnostics.beginGridPreload(catalogSize: 1200)
        diagnostics.markFirstUsableGrid(preloadID: preloadID)
        diagnostics.endGridPreload(preloadID: preloadID)
        diagnostics.endThumbnailWork()
        diagnostics.endThumbnailWork()

        let snapshot = diagnostics.snapshot()
        #expect(snapshot.coldThumbnailDecodes == 2)
        #expect(snapshot.duplicateThumbnailKeys == 1)
        #expect(snapshot.coalescedThumbnailWaiters == 1)
        #expect(snapshot.thumbnailCancellations == 1)
        #expect(snapshot.activeThumbnailWork == 0)
        #expect(snapshot.peakThumbnailWork == 2)
        #expect(snapshot.similarityInferenceStarts == 1)
        #expect(snapshot.semanticSearchStarts == 1)
        #expect(snapshot.deepReviewInferenceStarts == 1)
        #expect(snapshot.semanticHydrationStarts == 1)
        #expect(snapshot.modelDownloadStarts == 1)
        #expect(snapshot.gridPreloadStarts == 1)
        #expect(snapshot.latestGridCatalogSize == 1200)
        #expect(snapshot.latestFirstUsableGridMilliseconds != nil)
        #expect(RawImageLoadingConcurrency.thumbnailPreloadLimit >= 1)
        #expect(RawImageLoadingConcurrency.thumbnailPreloadLimit <= 4)
        #expect(MemoryDiagnosticsViewModel.tsvHeader.split(separator: "\t").count == 44)
    }

    private func makeFixture() async throws -> ThumbnailContentionFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ThumbnailContentionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceURL = root.appendingPathComponent("source.arw")
        try Data("synthetic raw source".utf8).write(to: sourceURL)
        let image = try makeCGImage()
        let loader = ContendedThumbnailImageLoader(image: image)
        let diagnostics = ContentionDiagnostics()
        let memoryCache = await makeIsolatedCache()
        let provider = RequestThumbnail(
            diskCache: DiskCacheManager(
                cacheDirectory: root.appendingPathComponent("Thumbnails", isDirectory: true),
            ),
            diagnostics: diagnostics,
            memoryCache: memoryCache,
            rawLoader: loader,
        )
        return ThumbnailContentionFixture(
            root: root,
            sourceURL: sourceURL,
            provider: provider,
            loader: loader,
            diagnostics: diagnostics,
        )
    }

    private func makeCGImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil,
            width: 32,
            height: 24,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        return try #require(context.makeImage())
    }
}

private func waitUntil(
    _ predicate: @escaping @Sendable () async -> Bool,
) async throws {
    for _ in 0 ..< 1000 {
        if await predicate() {
            return
        }
        try await Task.sleep(for: .milliseconds(2))
    }
    throw ThumbnailContentionTimeout()
}

private struct ThumbnailContentionTimeout: Error {}
