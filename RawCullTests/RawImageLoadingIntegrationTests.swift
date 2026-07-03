import AppKit
import Foundation
@testable import RawCull
import RawCullCore
import Testing

private actor FakeRawImageLoader: RawImageLoading {
    private(set) var thumbnailCGImageCalls = 0
    private(set) var thumbnailImageCalls = 0
    private(set) var previewCGImageCalls = 0
    private(set) var fileMetadataCalls = 0
    private let fileMetadataResult: RawImageFileMetadata?
    private let thumbnailCGImageResult: CGImage?
    private let thumbnailImageResult: NSImage?
    private let previewCGImageResult: CGImage?
    private let suspendPreviewUntilCancelled: Bool

    init(
        fileMetadataResult: RawImageFileMetadata? = nil,
        thumbnailCGImageResult: CGImage? = nil,
        thumbnailImageResult: NSImage? = nil,
        previewCGImageResult: CGImage? = nil,
        suspendPreviewUntilCancelled: Bool = false,
    ) {
        self.fileMetadataResult = fileMetadataResult
        self.thumbnailCGImageResult = thumbnailCGImageResult
        self.thumbnailImageResult = thumbnailImageResult
        self.previewCGImageResult = previewCGImageResult
        self.suspendPreviewUntilCancelled = suspendPreviewUntilCancelled
    }

    func fileMetadata(for _: URL) async -> RawImageFileMetadata? {
        fileMetadataCalls += 1
        return fileMetadataResult
    }

    func thumbnailCGImage(for _: URL, maxPixelSize _: Int) async -> CGImage? {
        thumbnailCGImageCalls += 1
        return thumbnailCGImageResult
    }

    func thumbnailImage(for _: URL, maxPixelSize _: Int) async -> NSImage? {
        thumbnailImageCalls += 1
        return thumbnailImageResult
    }

    func previewCGImage(for _: URL) async -> CGImage? {
        previewCGImageCalls += 1
        if suspendPreviewUntilCancelled {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return nil
        }
        return previewCGImageResult
    }
}

private func makeRawImageLoadingTestRoot(_ name: String = #function) throws -> URL {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeRawImageLoadingTestCGImage(
    width: Int = 32,
    height: Int = 24,
    color: NSColor = .red,
) throws -> CGImage {
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

struct RawImageLoadingIntegrationTests {
    @Test
    func `thumbnail request promotes source decode to memory for later hits`() async throws {
        let image = try makeRawImageLoadingTestCGImage()
        let fakeLoader = FakeRawImageLoader(thumbnailCGImageResult: image)
        let cache = await makeIsolatedCache()
        let diskRoot = try makeRawImageLoadingTestRoot()
        defer { try? FileManager.default.removeItem(at: diskRoot) }
        let provider = RequestThumbnail(
            diskCache: DiskCacheManager(cacheDirectory: diskRoot),
            memoryCache: cache,
            rawLoader: fakeLoader,
        )
        let rawURL = diskRoot.appendingPathComponent("source.arw")

        let first = await provider.requestThumbnail(for: rawURL, targetSize: 256)
        let second = await provider.requestThumbnail(for: rawURL, targetSize: 256)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await fakeLoader.thumbnailCGImageCalls == 1)
    }

    @Test
    func `full size preview loader saves extracted preview and reuses disk cache`() async throws {
        let fakeLoader = FakeRawImageLoader(
            previewCGImageResult: try makeRawImageLoadingTestCGImage(width: 40, height: 30),
        )
        let root = try makeRawImageLoadingTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawURL = root.appendingPathComponent("cached-preview.arw")
        let cache = FullSizeJPGDiskCache(cacheDirectory: root.appendingPathComponent("FullSizeJPGs", isDirectory: true))
        let loader = FullSizePreviewLoader(rawLoader: fakeLoader, fullSizeCache: cache)

        let first = await loader.loadEmbeddedPreview(for: rawURL)
        let second = await loader.loadEmbeddedPreview(for: rawURL)

        #expect(first != nil)
        #expect(second != nil)
        #expect(await fakeLoader.previewCGImageCalls == 1)
    }

    @Test
    func `full size preview loader prefers sidecar jpg before raw extraction`() async throws {
        let fakeLoader = FakeRawImageLoader(
            previewCGImageResult: try makeRawImageLoadingTestCGImage(width: 40, height: 30),
        )
        let root = try makeRawImageLoadingTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawURL = root.appendingPathComponent("sidecar-source.arw")
        let sidecarURL = FullSizePreviewLoader.sidecarJPEGURL(for: rawURL)
        let sidecarData = try #require(FullSizeJPGDiskCache.jpegData(from: makeRawImageLoadingTestCGImage(width: 20, height: 10)))
        try sidecarData.write(to: sidecarURL)
        let cache = FullSizeJPGDiskCache(cacheDirectory: root.appendingPathComponent("FullSizeJPGs", isDirectory: true))
        let loader = FullSizePreviewLoader(rawLoader: fakeLoader, fullSizeCache: cache)

        let image = await loader.loadEmbeddedPreview(for: rawURL)

        #expect(image?.width == 20)
        #expect(image?.height == 10)
        #expect(await fakeLoader.previewCGImageCalls == 0)
    }

    @Test
    func `cancelled full size preview load does not save extracted image`() async throws {
        let fakeLoader = FakeRawImageLoader(
            previewCGImageResult: try makeRawImageLoadingTestCGImage(width: 40, height: 30),
            suspendPreviewUntilCancelled: true,
        )
        let root = try makeRawImageLoadingTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawURL = root.appendingPathComponent("cancelled-source.arw")
        let cache = FullSizeJPGDiskCache(cacheDirectory: root.appendingPathComponent("FullSizeJPGs", isDirectory: true))
        let loader = FullSizePreviewLoader(rawLoader: fakeLoader, fullSizeCache: cache)

        let task = Task {
            await loader.loadEmbeddedPreview(for: rawURL)
        }
        for _ in 0 ..< 100 {
            if await fakeLoader.previewCGImageCalls > 0 {
                break
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        task.cancel()
        let result = await task.value

        #expect(result == nil)
        #expect(await cache.contains(for: rawURL) == false)
    }

    @Test
    func `scan files uses loader metadata for exif and focus point`() async throws {
        let metadata = RawImageFileMetadata(
            exifMetadata: ExifMetadata(
                shutterSpeed: "1/1000 s",
                focalLength: "400 mm",
                aperture: "f/5.6",
                apertureValue: 5.6,
                iso: "ISO 800",
                isoValue: 800,
                camera: "Sony A1",
                lensModel: "FE 400mm",
                rawFileType: "ARW",
                rawSizeClass: "L",
                pixelWidth: 8640,
                pixelHeight: 5760,
            ),
            focusLocation: "8640 5760 4320 2880",
            focusPoint: CGPoint(x: 0.5, y: 0.5),
        )
        let fakeLoader = FakeRawImageLoader(fileMetadataResult: metadata)
        let root = try makeRawImageLoadingTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let rawURL = root.appendingPathComponent("scan-source.arw")
        try Data([0x52, 0x41, 0x57]).write(to: rawURL)
        let scanner = ScanFiles(rawLoader: fakeLoader)

        let files = await scanner.scanFiles(url: root)

        let file = try #require(files.first)
        #expect(files.count == 1)
        #expect(file.exifData?.camera == "Sony A1")
        #expect(file.afFocusNormalized == CGPoint(x: 0.5, y: 0.5))
        #expect(await fakeLoader.fileMetadataCalls == 1)
        #expect(await scanner.decodedFocusPoints?.first?.focusLocation == "8640 5760 4320 2880")
    }
}
