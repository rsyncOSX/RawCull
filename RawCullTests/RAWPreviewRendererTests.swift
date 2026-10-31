import CoreGraphics
import Foundation
import Observation
@testable import RawCull
import Testing

@Suite("RAW display previews")
struct RAWPreviewRendererTests {
    private func preview() throws -> RAWPreviewRenderer.Preview {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
                                             bytesPerRow: 16, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try RAWPreviewRenderer.Preview(image: #require(context.makeImage()), nativeSize: CGSize(width: 4000, height: 4000))
    }

    @Test func `scale respects portrait landscape native and no upscaling`() {
        #expect(RAWPreviewRenderer.previewScale(nativeSize: CGSize(width: 6000, height: 4000), maximumDimension: 1200) == 0.2)
        #expect(RAWPreviewRenderer.previewScale(nativeSize: CGSize(width: 4000, height: 6000), maximumDimension: 1200) == 0.2)
        #expect(RAWPreviewRenderer.previewScale(nativeSize: CGSize(width: 640, height: 480), maximumDimension: 1280) == 1)
        #expect(RAWPreviewRenderer.previewScale(nativeSize: CGSize(width: 6000, height: 4000), maximumDimension: nil) == 1)
        #expect(RAWPreviewSizing.fitDimension(viewport: CGSize(width: 1440, height: 900), displayScale: 2) == 3072)
        #expect(RAWPreviewSizing.fitDimension(viewport: .zero, displayScale: 2) == nil)
        #expect(RAWPreviewSizing.fitDimension(viewport: CGSize(width: CGFloat.infinity, height: 900), displayScale: 2) == nil)
    }

    @Test func `cache retains pixels and native geometry and evicts least recently used`() throws {
        let urls = (0 ..< 3).map { _ in FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
        defer { for url in urls {
            try? FileManager.default.removeItem(at: url)
        } }
        for url in urls {
            try Data([1]).write(to: url)
        }
        let keys = try urls.map { try RAWPreviewCache.Key(url: $0, maximumDimension: 2560, inspectionExposureEV: nil) }
        let pixels = try preview()
        let cost = pixels.image.bytesPerRow * pixels.image.height
        var cache = RAWPreviewCache(byteLimit: cost * 2)
        cache.insert(pixels, for: keys[0])
        cache.insert(pixels, for: keys[1])
        #expect(cache.preview(for: keys[0])?.image === pixels.image)
        #expect(cache.preview(for: keys[0])?.nativeSize == pixels.nativeSize)
        cache.insert(pixels, for: keys[2])
        #expect(cache.preview(for: keys[1]) == nil)
        #expect(cache.byteCount == cost * 2)
        cache.removeAll()
        #expect(cache.byteCount == 0)
        #expect(cache.preview(for: keys[0]) == nil)
        var tiny = RAWPreviewCache(byteLimit: 1)
        tiny.insert(pixels, for: keys[0])
        #expect(tiny.byteCount == 0)
    }

    @Test func `cache separates fit native and inspection and invalidates replaced files`() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([1]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let fit = try RAWPreviewCache.Key(url: url, maximumDimension: 2560, inspectionExposureEV: nil)
        let native = try RAWPreviewCache.Key(url: url, maximumDimension: nil, inspectionExposureEV: nil)
        let inspection = try RAWPreviewCache.Key(url: url, maximumDimension: 2560, inspectionExposureEV: 0)
        let adjusted = try RAWPreviewCache.Key(url: url, maximumDimension: 2560, inspectionExposureEV: -1)
        let pixels = try preview()
        var cache = RAWPreviewCache(byteLimit: 1024)
        cache.insert(pixels, for: fit)
        #expect(cache.preview(for: native) == nil)
        #expect(cache.preview(for: inspection) == nil)
        cache.insert(pixels, for: native)
        cache.insert(pixels, for: inspection)
        cache.insert(pixels, for: adjusted)
        #expect(cache.preview(for: inspection) == nil)
        #expect(cache.preview(for: fit) != nil)
        #expect(cache.preview(for: native) != nil)
        try Data([1, 2]).write(to: url)
        let replaced = try RAWPreviewCache.Key(url: url, maximumDimension: 2560, inspectionExposureEV: nil)
        #expect(cache.preview(for: replaced) == nil)
        cache.insert(pixels, for: replaced)
        #expect(cache.preview(for: fit) == nil)
        #expect(cache.preview(for: native) == nil)
    }

    @Test @MainActor func `native launch and zoom request full sensor resolution`() {
        let session = ZoomSessionModel()
        #expect(session.rawPreviewMaximumDimension == 2560)
        session.pendingInitialZoomMode = .actualPixels
        #expect(session.rawPreviewMaximumDimension == nil)
        session.pendingInitialZoomMode = nil
        session.viewport.scale = 2
        #expect(session.rawPreviewMaximumDimension == nil)
        session.viewport.scale = 1
        session.rawFitPreviewDimension = 3072
        #expect(session.rawPreviewMaximumDimension == 3072)
        session.evaluateRAWExposure = true
        #expect(session.rawPreviewMaximumDimension == nil)
    }

    @Test @MainActor func `resizes coalesce until current RAW load finishes and stale completion is ignored`() throws {
        let session = ZoomSessionModel()
        session.sourceSelection.select(.developedRAW)
        let first = try #require(session.beginPreviewLoad(preservingImage: false))
        session.rawFitPreviewDimension = 3072
        #expect(session.beginPreviewLoad(preservingImage: true) == nil)
        session.rawFitPreviewDimension = 3840
        #expect(session.beginPreviewLoad(preservingImage: true) == nil)
        #expect(session.finishPreviewLoad(first))
        let next = try #require(session.beginPreviewLoad(preservingImage: true))
        #expect(session.rawPreviewMaximumDimension == 3840)
        #expect(!session.finishPreviewLoad(first))
        #expect(session.isLoadingRAWPreview)
        #expect(session.finishPreviewLoad(next))
        #expect(!session.isLoadingRAWPreview)
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func `display is published while analysis thumbnail is still waiting`() async throws {
        let model = makeRawCullViewModel()
        let gate = RAWPreviewTestGate()
        let pixels = try preview()
        var task: Task<Void, Never>?
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = model.zoomOverlayCGImage
            } onChange: {
                continuation.resume()
            }
            task = ZoomPreviewHandler.handleOverlay(file: makeCullingTestFile("display.ARW"), source: .developedRAW,
                                                    viewModel: model, renderRAW: { _, _, _ in pixels }, loadAnalysis: { _, _ in
                                                        await gate.wait()
                                                        return pixels.image
                                                    })
        }
        #expect(model.zoomOverlayCGImage === pixels.image)
        #expect(model.zoomOverlayAnalysisCGImage == nil)
        await gate.waitUntilEntered()
        await gate.release()
        await task?.value
        #expect(model.zoomOverlayAnalysisCGImage === pixels.image)
    }

    @Test func `fit view reuses an existing developed JPEG but inspection never does`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("cached.ARW")
        try Data("not RAW data".utf8).write(to: source)
        let disk = FullSizeJPGDiskCache(cacheDirectory: root.appendingPathComponent("cache"))
        let input = try preview()
        let jpeg = try #require(FullSizeJPGDiskCache.jpegData(from: input.image))
        await disk.save(jpeg, for: source, variant: .developedRAW)
        let renderer = RAWPreviewRenderer()
        let loaded = try await ZoomPreviewHandler.loadOverlayRAWPreview(
            url: source, maximumDimension: 2560, inspectionExposureEV: nil, renderer: renderer, diskCache: disk
        )
        #expect(loaded.image.width == 4)
        #expect(loaded.nativeSize == CGSize(width: 4, height: 4))
        await #expect(throws: RAWPreviewRenderer.RenderError.self) {
            try await ZoomPreviewHandler.loadOverlayRAWPreview(
                url: source, maximumDimension: nil, inspectionExposureEV: 0, renderer: renderer, diskCache: disk
            )
        }
    }

    @Test func `malformed source reports decoding failure`() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ARW")
        try Data("not a RAW file".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = RAWPreviewRenderer()
        await #expect(throws: RAWPreviewRenderer.RenderError.self) { try await renderer.render(url: url) }
    }

    @Test func `cancelled render fails before opening source`() async {
        let renderer = RAWPreviewRenderer()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await renderer.render(url: URL(fileURLWithPath: "/does-not-exist.ARW"))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test(.timeLimit(.minutes(1))) @MainActor
    func `cancelled old image cannot replace next selection`() async throws {
        let model = makeRawCullViewModel()
        let gate = RAWPreviewTestGate()
        let pixels = try preview()
        let oldPixels = try preview()
        let old = ZoomPreviewHandler.handleOverlay(file: makeCullingTestFile("old.ARW"), source: .developedRAW,
                                                   viewModel: model, renderRAW: { _, _, _ in
                                                       await gate.wait()
                                                       return oldPixels // Deliberately ignores cancellation, like an in-progress Core Image render.
                                                   }, loadAnalysis: { _, _ in nil })
        await gate.waitUntilEntered()
        old.cancel()
        let next = ZoomPreviewHandler.handleOverlay(file: makeCullingTestFile("next.ARW"), source: .developedRAW,
                                                    viewModel: model, renderRAW: { _, _, _ in pixels }, loadAnalysis: { _, _ in nil })
        await next.value
        let current = model.zoomOverlayCGImage
        await gate.release()
        await old.value
        #expect(model.zoomOverlayCGImage === current)
        #expect(current === pixels.image)
        #expect(model.zoomOverlayNativeSize == pixels.nativeSize)
    }
}

private actor RAWPreviewTestGate {
    private var entered = false
    private var entryWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if entered {
            return
        }
        await withCheckedContinuation { entryWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume(); releaseWaiter = nil
    }
}
