#if DEBUG
    @testable import CoreAICLIPBackend
    import CoreAIShared
    import PhotoAIContracts
#endif
import CoreGraphics
import CoreImage
import Darwin
import Foundation
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

@Suite("Combined Review source and coordinates", .tags(.smoke))
struct ReviewImageSourceTests {
    @Test(arguments: 1 ... 8)
    func `orientation and source crops`(_ orientation: Int) async throws {
        let url = try fixture(width: 120, height: 80, orientation: orientation)
        defer { try? FileManager.default.removeItem(at: url) }
        var request = ReviewSourceRequest(url: url, preference: .highQualityPreview, policy: .appearance)
        request.overviewMaximumDimension = 32
        let source = try await ReviewImageSourceService().load(request)
        #expect(source.image.width == (orientation >= 5 ? 80 : 120))
        #expect(source.image.height == (orientation >= 5 ? 120 : 80))
        #expect(source.metadata.originalOrientation == UInt32(orientation))
        #expect(source.metadata.fidelity == .fullRaster)
        let transform = source.metadata.orientationTransform
        let encodedRect = CGRect(x: 10, y: 5, width: 20, height: 30)
        let normalizedRect = try transform.normalizedRect(fromEncoded: encodedRect)
        #expect(try transform.encodedRect(fromNormalized: normalizedRect) == encodedRect)
        #expect(transform.normalizedSpace == source.metadata.sourceSpace)
        let order = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                     [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]][orientation - 1]
        let corners = [(0.1, 0.1), (0.9, 0.1), (0.1, 0.9), (0.9, 0.9)]
        for (index, corner) in corners.enumerated() {
            let rect = CGRect(x: CGFloat(source.image.width) * corner.0 - 2,
                              y: CGFloat(source.image.height) * corner.1 - 2, width: 4, height: 4)
            let region = try source.region(rect: rect, padding: 0, purpose: "corner",
                                           encoder: .init(width: 448, height: 448, strategy: .stretch))
            let crop = try source.crop(region)
            let actual = try rgb(crop)
            let expected = colors[order[index]]
            for channel in 0 ..< 3 {
                #expect(abs(Int(actual[channel]) - Int(expected[channel])) <= 2)
            }
            #expect(crop.width == 4)
            #expect(crop.height == 4)
            // Actual full-source crops retain four pixels despite a much smaller overview.
            let mapped = try source.metadata.sourceSpace.map(region.sourceRect, to: source.overviewSpace)
            let roundTrip = try source.overviewSpace.map(mapped, to: source.metadata.sourceSpace)
            #expect(abs(roundTrip.minX - region.sourceRect.minX) < 0.000001)
            #expect(abs(roundTrip.minY - region.sourceRect.minY) < 0.000001)
        }
    }

    @Test(arguments: [CGSize(width: 900, height: 600), CGSize(width: 600, height: 900),
                      CGSize(width: 600, height: 600), CGSize(width: 1800, height: 180)])
    func `coordinate and encoder round trips`(_ size: CGSize) throws {
        let space = try ReviewCoordinateSpace(width: Int(size.width), height: Int(size.height))
        let normalized = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4)
        let rect = try space.sourceRect(fromNormalized: normalized)
        #expect(rect.minX == size.width * 0.1)
        #expect(rect.minY == size.height * 0.2)
        for strategy in [ReviewEncoderGeometry.Strategy.stretch, .shortestSideCenterCrop] {
            let trace = try ReviewEncoderGeometry(width: 224, height: 224, strategy: strategy).trace(crop: space.bounds)
            let original = CGPoint(x: trace.retainedSourceRect.midX, y: trace.retainedSourceRect.midY)
            let mapped = trace.encoderPoint(fromSource: original)
            let recovered = trace.sourcePoint(fromEncoder: mapped)
            #expect(abs(original.x - recovered.x) < 0.000001)
            #expect(abs(original.y - recovered.y) < 0.000001)
            #expect(space.bounds.contains(trace.retainedSourceRect))
            #expect(abs(mapped.x - 112) < 0.000001)
            #expect(abs(mapped.y - 112) < 0.000001)
            if strategy == .stretch {
                #expect(trace.retainedSourceRect == space.bounds)
            } else {
                #expect(trace.retainedSourceRect.width == trace.retainedSourceRect.height)
            }
        }
    }

    @Test
    func `clipping stable IDs and invalid bounds`() throws {
        let space = try ReviewCoordinateSpace(width: 100, height: 80)
        let encoder = ReviewEncoderGeometry(width: 448, height: 448, strategy: .stretch)
        let rect = CGRect(x: 0, y: 0, width: 20, height: 30)
        let region = try ReviewRegion.make(sourceID: "source", space: space, rect: rect, purpose: "subject", encoder: encoder)
        #expect(region.edgeClipped)
        #expect(region.paddedRect.minX == -3)
        #expect(region.sourceRect == CGRect(x: 0, y: 0, width: 23, height: 35))
        #expect(region.encoder.upscalesSource)
        #expect(try region.id == (ReviewRegion.make(sourceID: "source", space: space, rect: rect, purpose: "subject", encoder: encoder)).id)
        #expect(try region.id != (ReviewRegion.make(sourceID: "other", space: space, rect: rect, purpose: "subject", encoder: encoder)).id)
        #expect(throws: ReviewImageError.self) {
            try ReviewRegion.make(sourceID: "source", space: space,
                                  rect: CGRect(x: -1, y: 0, width: 20, height: 20), purpose: "bad", encoder: encoder)
        }
        #expect(throws: ReviewImageError.self) {
            try space.sourceRect(fromNormalized: CGRect(x: 0, y: 0, width: 2, height: 1))
        }
    }

    @Test
    func `render isolation and lossless retention`() async throws {
        let url = try fixture(width: 120, height: 80)
        defer { try? FileManager.default.removeItem(at: url) }
        let service = ReviewImageSourceService()
        let appearance = try await service.load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        let technical = try await service.load(.init(url: url, preference: .rawDetail, policy: .technical))
        #expect(appearance.metadata.identity != technical.metadata.identity)
        #expect(appearance.metadata.fileIdentity == technical.metadata.fileIdentity)
        #expect(appearance.metadata.sourceSpace == technical.metadata.sourceSpace)
        #expect(technical.metadata.fidelity == .fullRaster)
        #expect(try appearance.mapSourceRect(CGRect(x: 0, y: 0, width: 20, height: 20), to: technical) == CGRect(x: 0, y: 0, width: 20, height: 20))
        let region = try appearance.region(rect: CGRect(x: 5, y: 5, width: 11, height: 13), padding: 0,
                                           purpose: "detail", encoder: .init(width: 448, height: 448, strategy: .stretch))
        #expect(throws: ReviewImageError.self) { try technical.crop(region) }
        let input = try appearance.crop(region)
        let bytes = try ReviewImageSource.pngData(for: input)
        let source = try #require(CGImageSourceCreateWithData(bytes as CFData, nil))
        let restored = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(restored.width == input.width)
        #expect(restored.height == input.height)
        #expect(try rgb(restored) == rgb(input))
    }

    @Test
    func `unsupported RAW fallback is explicit`() async throws {
        let rasterURL = try fixture(width: 120, height: 80)
        let url = rasterURL.deletingPathExtension().appendingPathExtension("unsupportedraw")
        try Data("unsupported RAW".utf8).write(to: url)
        defer {
            try? FileManager.default.removeItem(at: rasterURL)
            try? FileManager.default.removeItem(at: url)
        }
        let imageSource = try #require(CGImageSourceCreateWithURL(rasterURL as CFURL, nil))
        let preview = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let service = ReviewImageSourceService(previewLoader: FixturePreviewLoader(image: preview))
        let source = try await service.load(.init(url: url, preference: .rawDetail, policy: .technical))
        #expect(source.metadata.fidelity == .embeddedCameraPreview)
        #expect(source.metadata.limitations.contains("rawDemosaicUnavailable; using embedded camera preview"))
        #expect(source.metadata.renderSettings["processing"] == "Camera authored; sharpening/noise/exposure unknown")
        #expect(source.metadata.renderSettings["sharpnessAmount"] == nil)
    }

    @Test
    func `embedded loader never substitutes sidecar`() throws {
        let rasterURL = try fixture(width: 120, height: 80)
        let rawURL = rasterURL.deletingPathExtension().appendingPathExtension("arw")
        let sidecarURL = rawURL.deletingPathExtension().appendingPathExtension("jpg")
        try Data("unsupported RAW".utf8).write(to: rawURL)
        try FileManager.default.moveItem(at: rasterURL, to: sidecarURL)
        defer {
            try? FileManager.default.removeItem(at: rawURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }
        let request = ReviewSourceRequest(url: rawURL, preference: .highQualityPreview, policy: .appearance)
        #expect(try ReviewEmbeddedPreviewLoader().load(request) == nil)
    }

    @Test
    func `cancellation does not return source`() async throws {
        let url = try fixture(width: 120, height: 80)
        defer { try? FileManager.default.removeItem(at: url) }
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        }
        await #expect(throws: CancellationError.self) { try await worker.value }
    }

    @Test
    func `wide gamut ICC conversion`() async throws {
        let inputSpace = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let authored = [UInt8(180), 90, 45]
        let url = try fixture(width: 120, height: 80, customColors: Array(repeating: authored, count: 4), colorSpace: inputSpace)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        let inputColor = try #require(CGColor(colorSpace: inputSpace, components: [180.0 / 255, 90.0 / 255, 45.0 / 255, 1]))
        let outputSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let expected = try #require(inputColor.converted(to: outputSpace, intent: .relativeColorimetric, options: nil)?.components)
        let actual = try rgb(source.image)
        for channel in 0 ..< 3 {
            #expect(abs(Double(actual[channel]) - Double(expected[channel]) * 255) < 3)
        }
        #expect(actual != authored)
        #expect(source.metadata.inputColorSpace.contains("DisplayP3"))
        #expect(source.image.colorSpace?.name == CGColorSpace.sRGB)
        #expect(source.image.bitsPerComponent == 8)
        #expect(source.metadata.renderSettings["HDR"]?.contains("toneMapHDRtoSDR") == true)
    }

    @Test
    func `HDR render is finite SDR`() async throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.itur_2100_PQ))
        var bytes = [UInt8](repeating: 190, count: 16 * 16 * 4)
        for index in 0 ..< 256 {
            bytes[index * 4 + 3] = 255
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32,
                                         bytesPerRow: 64, space: colorSpace,
                                         bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let ci = CIImage(cgImage: image, options: [.toneMapHDRtoSDR: true, .expandToHDR: false])
        let rendered = try #require(ReviewImageSourceService.render(ci, extent: ci.extent))
        #expect(rendered.colorSpace?.name == CGColorSpace.sRGB)
        #expect(rendered.bitsPerComponent == 8)
        let values = try rgb(rendered)
        #expect(values[0] > 0)
        #expect(values[0] == values[1])
        #expect(values[1] == values[2])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-hdr-\(UUID()).tiff")
        defer { try? FileManager.default.removeItem(at: url) }
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        let sourcePixels = try rgb(source.image)
        for channel in 0 ..< 3 {
            #expect(abs(Int(sourcePixels[channel]) - Int(values[channel])) <= 2)
        }
    }

    @Test
    func `memory admission rejects before decode`() throws {
        let request = ReviewSourceRequest(url: URL(filePath: "/unused"), preference: .rawDetail, policy: .technical)
        #expect(try ReviewImageSourceService.admit(width: 6000, height: 4000, request: request) == 1_920_000_000)
        #expect(throws: ReviewImageError.self) { try ReviewImageSourceService.admit(width: 12000, height: 8000, request: request) }
        #expect(throws: ReviewImageError.self) { try ReviewImageSourceService.admit(width: Int.max, height: 2, request: request) }
    }

    #if DEBUG
        @Test
        func `actual preprocessors retain source crop evidence`() async throws {
            let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            let url = root.appendingPathComponent("Docs/CombinedReviewInputFixtures/source-landscape.png")
            let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
            let qwen = ReviewEncoderGeometry(width: 448, height: 448, strategy: .stretch)
            let clip = ReviewEncoderGeometry(width: 224, height: 224, strategy: .shortestSideCenterCrop)
            let full = source.metadata.sourceSpace.bounds
            let qwenRegion = try source.region(rect: full, padding: 0, purpose: "overview", encoder: qwen)
            let clipRegion = try source.region(rect: full, padding: 0, purpose: "overview", encoder: clip)
            #expect(qwenRegion.intendedRegionRetained)
            #expect(!clipRegion.intendedRegionRetained)
            #expect(clipRegion.encoder.retainedSourceRect == CGRect(x: 150, y: 0, width: 600, height: 600))
            let processor = ImagePreprocessor(targetSize: CGSize(width: 448, height: 448),
                                              mean: (0, 0, 0), std: (1, 1, 1), rescaleFactor: 1)
            let wholeQwen = try processor.preprocessCHW(cgImage: source.crop(qwenRegion), strategy: .stretch)
            let clipMetadata = ModelImagePreprocessingMetadata(version: "geometry-fixture-v1", width: 224, height: 224,
                                                               resize: "shortest-side", crop: "center", interpolation: "bicubic",
                                                               mean: [0, 0, 0], standardDeviation: [1, 1, 1])
            let wholeCLIP = try CoreAICLIPProvider.preprocessCLIPImage(source.crop(clipRegion), preprocessing: clipMetadata)
            #expect(wholeQwen.count == 3 * 448 * 448)
            #expect(wholeCLIP.count == 3 * 224 * 224)
            // The red corner survives Qwen stretch and is removed by CLIP center crop.
            #expect(wholeQwen[22 * 448 + 22] > 0.95)
            #expect(wholeCLIP[11 * 224 + 11] < 0.5)
            let corner = CGRect(x: 5, y: 5, width: 30, height: 30)
            let region = try source.region(rect: corner, padding: 0, purpose: "detail", encoder: clip)
            #expect(region.intendedRegionRetained)
            let crop = try source.crop(region)
            let detail = try CoreAICLIPProvider.preprocessCLIPImage(crop, preprocessing: clipMetadata)
            let qwenDetail = try processor.preprocessCHW(cgImage: crop, strategy: .stretch)
            #expect(detail[112 * 224 + 112] > 0.95)
            #expect(qwenDetail[224 * 448 + 224] > 0.95)
            #expect(detail.allSatisfy { $0.isFinite })
            #expect(qwenDetail.allSatisfy { $0.isFinite })
        }
    #endif

    @Test
    func `full source working set`() async throws {
        var initialUsage = rusage()
        getrusage(RUSAGE_SELF, &initialUsage)
        let url = try fixture(width: 6000, height: 4000)
        defer { try? FileManager.default.removeItem(at: url) }
        let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .technical))
        #expect(source.image.width == 6000)
        #expect(source.image.height == 4000)
        let region = try source.region(rect: CGRect(x: 100, y: 100, width: 448, height: 448), padding: 0,
                                       purpose: "detail", encoder: .init(width: 448, height: 448, strategy: .stretch))
        let crop = try source.crop(region)
        let png = try ReviewImageSource.pngData(for: crop)
        #expect(!png.isEmpty)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("Review full-source working set: 6000x4000; retainedBytes=\(source.metadata.retainedImageBytes); processHighWaterBytes=\(usage.ru_maxrss); conservativeEstimate=\(source.metadata.estimatedWorkingBytes)")
        do {
            let report: [String: Any] = ["sourceWidth": 6000, "sourceHeight": 4000,
                                         "retainedImageBytes": source.metadata.retainedImageBytes,
                                         "processHighWaterBytes": usage.ru_maxrss,
                                         "initialProcessHighWaterBytes": initialUsage.ru_maxrss,
                                         "estimatedWorkingBytes": source.metadata.estimatedWorkingBytes,
                                         "physicalMemoryBytes": ProcessInfo.processInfo.physicalMemory,
                                         "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                         "scope": "Synthetic full raster, test host and fixture allocation included; no models or RAW demosaic"]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            Attachment.record(String(decoding: data, as: UTF8.self), named: "full-source-memory.json")
        }
    }

    private var colors: [[UInt8]] {
        [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]
    }

    private func fixture(width: Int, height: Int, orientation: Int = 1, customColors: [[UInt8]]? = nil,
                         colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!) throws -> URL {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let fixtureColors = customColors ?? colors
        for row in 0 ..< height {
            for column in 0 ..< width {
                let color = fixtureColors[(row < height / 2 ? 0 : 2) + (column < width / 2 ? 0 : 1)]
                let offset = (row * width + column) * 4
                bytes[offset] = color[0]; bytes[offset + 1] = color[1]; bytes[offset + 2] = color[2]
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                         bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("review-fixture-\(UUID()).tiff")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        return url
    }

    private func rgb(_ image: CGImage) throws -> [UInt8] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return [bytes[0], bytes[1], bytes[2]]
    }
}

private nonisolated struct FixturePreviewLoader: ReviewEmbeddedPreviewLoading {
    let image: CGImage
    func load(_: ReviewSourceRequest) throws -> ReviewEmbeddedPreview? {
        ReviewEmbeddedPreview(image: image, encodedSize: CGSize(width: image.width, height: image.height), orientation: 1)
    }
}
