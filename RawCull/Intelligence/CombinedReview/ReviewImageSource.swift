import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import RawParserKit
import UniformTypeIdentifiers

nonisolated enum ReviewRenderPolicy: String, Sendable {
    case appearance, technical
}

nonisolated enum ReviewSourcePreference: String, Sendable {
    case highQualityPreview, rawDetail
}

nonisolated struct ReviewSourceRequest: Sendable {
    let url: URL
    let preference: ReviewSourcePreference
    let policy: ReviewRenderPolicy
    var overviewMaximumDimension = 2048
    /// Conservative allocation guard, not a measured decoder peak guarantee.
    /// Larger sources require an explicitly raised limit after memory qualification.
    var maximumSourcePixels = 24_000_000
    var maximumEstimatedWorkingBytes = 2_000_000_000
}

nonisolated struct ReviewSourceMetadata: Sendable {
    nonisolated enum Fidelity: String, Sendable { case embeddedCameraPreview, fullRaster, rawDemosaic }
    let identity: String
    let fileIdentity: String
    let fidelity: Fidelity
    let policy: ReviewRenderPolicy
    let sourceSpace: ReviewCoordinateSpace
    let encodedSize: CGSize
    let originalOrientation: UInt32
    let orientationTransform: ReviewOrientationTransform
    let inputColorSpace: String
    let outputColorSpace: String
    let renderSettings: [String: String]
    let limitations: [String]
    let estimatedWorkingBytes: Int
    let retainedImageBytes: Int
}

/// Immutable renders. Crops always come from this full declared source, never the overview.
nonisolated struct ReviewImageSource: Sendable {
    let image: CGImage
    let overview: CGImage
    let metadata: ReviewSourceMetadata

    var overviewSpace: ReviewCoordinateSpace {
        // Dimensions originate from successfully decoded CGImages.
        ReviewCoordinateSpace(image: overview)
    }

    func region(rect: CGRect, padding: CGFloat = 0.15, purpose: String,
                encoder: ReviewEncoderGeometry) throws -> ReviewRegion {
        try ReviewRegion.make(sourceID: metadata.identity, space: metadata.sourceSpace,
                              rect: rect, padding: padding, purpose: purpose, encoder: encoder)
    }

    func crop(_ region: ReviewRegion) throws -> CGImage {
        // Prevent stale regions or regions from another render being applied to this image.
        guard region.sourceID == metadata.identity,
              metadata.sourceSpace.bounds.contains(region.sourceRect),
              let result = image.cropping(to: region.sourceRect)
        else {
            throw ReviewImageError.invalidGeometry
        }
        return result
    }

    func mapSourceRect(_ rect: CGRect, to other: ReviewImageSource) throws -> CGRect {
        guard metadata.fileIdentity == other.metadata.fileIdentity,
              metadata.fidelity == other.metadata.fidelity,
              metadata.orientationTransform == other.metadata.orientationTransform,
              metadata.sourceSpace == other.metadata.sourceSpace
        else {
            throw ReviewImageError.unsupportedAlignment
        }
        guard metadata.sourceSpace.bounds.contains(rect) else { throw ReviewImageError.invalidGeometry }
        return rect
    }

    /// Lossless caller-controlled retention hook; no cache or retention policy is implied.
    static func pngData(for exactInput: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ReviewImageError.decodeFailed
        }
        CGImageDestinationAddImage(destination, exactInput, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ReviewImageError.decodeFailed }
        return data as Data
    }
}

nonisolated protocol ReviewImageSourceLoading: Sendable {
    func load(_ request: ReviewSourceRequest) async throws -> ReviewImageSource
}

nonisolated struct ReviewImageSourceService: ReviewImageSourceLoading {
    let previewLoader: any ReviewEmbeddedPreviewLoading

    init(previewLoader: any ReviewEmbeddedPreviewLoading = ReviewEmbeddedPreviewLoader()) {
        self.previewLoader = previewLoader
    }

    @concurrent
    func load(_ request: ReviewSourceRequest) async throws -> ReviewImageSource {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [request.url])
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        guard request.overviewMaximumDimension > 0 else { throw ReviewImageError.invalidGeometry }
        let before = try Self.fileIdentity(request.url)
        let rendered = SupportedFileType.isRenderedImage(request.url) || ["heic", "heif"].contains(request.url.pathExtension.lowercased())
        let source = CGImageSourceCreateWithURL(request.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let properties = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
        var orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        var settings = ["renderVersion": "review-srgb-v1", "decoderOS": ProcessInfo.processInfo.operatingSystemVersionString, "HDR": "CoreImage toneMapHDRtoSDR; gain-map expansion disabled",
                        "output": "sRGB RGBA8 SDR", "policy": request.policy.rawValue]
        var limitations: [String] = []
        var fidelity: ReviewSourceMetadata.Fidelity
        var decoded: CGImage
        var encodedSize: CGSize
        var estimatedBytes: Int

        if rendered {
            guard let source,
                  let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
            else {
                throw ReviewImageError.decodeFailed
            }
            estimatedBytes = try Self.admit(width: pixelWidth, height: pixelHeight, request: request)
            encodedSize = CGSize(width: pixelWidth, height: pixelHeight)
            // Transform once, at original resolution. No thumbnail/grid cache is used.
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary) else { throw ReviewImageError.decodeFailed }
            decoded = image
            fidelity = .fullRaster
            settings["processing"] = "Authored raster; no added sharpening/noise reduction"
        } else {
            var rawResult: CGImage?
            var rawSize: CGSize?
            var rawEstimate: Int?
            if request.preference == .rawDetail, let filter = CIRAWFilter(imageURL: request.url),
               filter.nativeSize.width.isFinite, filter.nativeSize.height.isFinite,
               filter.nativeSize.width > 0, filter.nativeSize.height > 0 {
                filter.scaleFactor = 1
                filter.isDraftModeEnabled = false
                filter.extendedDynamicRangeAmount = 0
                orientation = filter.orientation.rawValue
                let native = filter.nativeSize
                rawEstimate = try Self.admit(width: Int(native.width), height: Int(native.height), request: request)
                rawSize = native
                if request.policy == .technical {
                    // Match the existing Deep Review parameters. Decoder-dependent noise
                    // defaults are retained and recorded rather than silently changed.
                    filter.sharpnessAmount = 0
                    filter.detailAmount = 0.6
                    filter.contrastAmount = 1
                    filter.exposure = 0
                }
                settings["decoderVersion"] = filter.decoderVersion.rawValue
                settings["scaleFactor"] = String(filter.scaleFactor)
                settings["draftMode"] = String(filter.isDraftModeEnabled)
                settings["extendedDynamicRangeAmount"] = String(filter.extendedDynamicRangeAmount)
                settings["baselineExposure"] = String(filter.baselineExposure)
                settings["shadowBias"] = String(filter.shadowBias)
                settings["boostAmount"] = String(filter.boostAmount)
                settings["boostShadowAmount"] = String(filter.boostShadowAmount)
                settings["localToneMapAmount"] = String(filter.localToneMapAmount)
                settings["neutralTemperature"] = String(filter.neutralTemperature)
                settings["neutralTint"] = String(filter.neutralTint)
                settings["lensCorrection"] = String(filter.isLensCorrectionEnabled)
                settings["gamutMapping"] = String(filter.isGamutMappingEnabled)
                settings["moireReductionAmount"] = String(filter.moireReductionAmount)
                settings["despeckleAmount"] = String(filter.despeckleAmount)
                settings["sharpnessAmount"] = String(filter.sharpnessAmount)
                settings["detailAmount"] = String(filter.detailAmount)
                settings["contrastAmount"] = String(filter.contrastAmount)
                settings["exposure"] = String(filter.exposure)
                settings["luminanceNoiseReductionAmount"] = String(filter.luminanceNoiseReductionAmount)
                settings["colorNoiseReductionAmount"] = String(filter.colorNoiseReductionAmount)
                settings["noisePolicy"] = "Recorded decoder defaults; existing scoring parameters"
                settings["orientation"] = "CIRAWFilter native metadata orientation"
                settings["HDR"] = "CIRAWFilter default tone curve; SDR sRGB RGBA8 output"
                try Task.checkCancellation()
                if let output = filter.outputImage {
                    rawResult = Self.render(output, extent: output.extent)
                }
            }
            if let rawResult, let rawSize, let rawEstimate {
                decoded = rawResult
                encodedSize = rawSize
                estimatedBytes = rawEstimate
                fidelity = .rawDemosaic
            } else {
                if request.preference == .rawDetail {
                    limitations.append("rawDemosaicUnavailable; using embedded camera preview")
                }
                guard let preview = try previewLoader.load(request) else { throw ReviewImageError.decodeFailed }
                decoded = preview.image
                encodedSize = preview.encodedSize
                orientation = preview.orientation
                estimatedBytes = try Self.admit(width: decoded.width, height: decoded.height, request: request)
                fidelity = .embeddedCameraPreview
                settings = ["renderVersion": "review-srgb-v1", "decoderOS": ProcessInfo.processInfo.operatingSystemVersionString, "policy": request.policy.rawValue,
                            "processing": "Camera authored; sharpening/noise/exposure unknown",
                            "HDR": "CoreImage toneMapHDRtoSDR; gain-map expansion disabled", "output": "sRGB RGBA8 SDR"]
            }
        }
        try Task.checkCancellation()
        let inputColorSpace = decoded.colorSpace?.name.map { $0 as String } ?? "untagged; assumed sRGB"
        if fidelity != .rawDemosaic {
            let ci = CIImage(cgImage: decoded, options: [.toneMapHDRtoSDR: true, .expandToHDR: false])
            guard let converted = Self.render(ci, extent: ci.extent) else { throw ReviewImageError.decodeFailed }
            decoded = converted
        }
        if fidelity == .embeddedCameraPreview {
            limitations.append("Camera processing and preview resolution limit technical evidence; no RAW recovery claims")
        }
        limitations.append("Output is SDR RGBA8; higher precision source values are not retained")
        let space = try ReviewCoordinateSpace(width: decoded.width, height: decoded.height)
        let orientationTransform = try ReviewOrientationTransform(width: Int(encodedSize.width), height: Int(encodedSize.height), orientation: orientation)
        guard orientationTransform.normalizedSpace == space else { throw ReviewImageError.unsupportedAlignment }
        let overview = try Self.overview(decoded, maximumDimension: request.overviewMaximumDimension)
        guard try before == Self.fileIdentity(request.url) else { throw ReviewImageError.sourceChanged }
        let settingsKey = settings.keys.sorted().map { "\($0)=\(settings[$0]!)" }.joined(separator: "|")
        try Task.checkCancellation()
        let identity = Self.hash("\(before)|\(fidelity.rawValue)|\(decoded.width)x\(decoded.height)|\(settingsKey)")
        return ReviewImageSource(image: decoded, overview: overview,
                                 metadata: ReviewSourceMetadata(identity: identity, fileIdentity: before, fidelity: fidelity,
                                                                policy: request.policy, sourceSpace: space, encodedSize: encodedSize, originalOrientation: orientation, orientationTransform: orientationTransform,
                                                                inputColorSpace: inputColorSpace, outputColorSpace: "sRGB", renderSettings: settings,
                                                                limitations: limitations, estimatedWorkingBytes: estimatedBytes,
                                                                retainedImageBytes: decoded.bytesPerRow * decoded.height + overview.bytesPerRow * overview.height))
    }

    static func admit(width: Int, height: Int, request: ReviewSourceRequest) throws -> Int {
        guard width > 0, height > 0 else { throw ReviewImageError.invalidGeometry }
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 80)
        guard !overflow, !byteOverflow, pixels <= request.maximumSourcePixels,
              bytes <= request.maximumEstimatedWorkingBytes else { throw ReviewImageError.memoryAdmissionDenied }
        return bytes
    }

    static func render(_ image: CIImage, extent: CGRect) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CIContext(options: [.cacheIntermediates: false,
                                          .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        return context.createCGImage(image, from: extent, format: .RGBA8, colorSpace: space)
    }

    private static func overview(_ image: CGImage, maximumDimension: Int) throws -> CGImage {
        let scale = min(1, CGFloat(maximumDimension) / CGFloat(max(image.width, image.height)))
        if scale == 1 {
            return image
        }
        let pixelWidth = max(1, Int(CGFloat(image.width) * scale))
        let pixelHeight = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ReviewImageError.decodeFailed }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        guard let result = context.makeImage() else { throw ReviewImageError.decodeFailed }
        return result
    }

    private static func fileIdentity(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        return hash("\(url.standardizedFileURL.path)|\(values.fileSize ?? -1)|\(values.contentModificationDate?.timeIntervalSince1970 ?? -1)|\(String(describing: values.fileResourceIdentifier))")
    }

    private static func hash(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
