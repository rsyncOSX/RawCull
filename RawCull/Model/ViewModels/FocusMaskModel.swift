import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import Vision

struct FocusDetectorConfig {
    var preBlurRadius: Float = 1.92
    var threshold: Float = 0.46
    var dilationRadius: Float = 0.43
    var energyMultiplier: Float = 7.62
    var erosionRadius: Float = 0.27
    var featherRadius: Float = 2.0
    var showRawLaplacian: Bool = false
}

// Explicit nonisolated conformance so the @Observable macro's change-tracking
// code can call == from a nonisolated context (config is nonisolated(unsafe)).
// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor would make the synthesized == @MainActor,
// blocking the nonisolated call site — so we must spell it out manually.
// swiftformat:disable:next redundantEquatable
extension FocusDetectorConfig: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.preBlurRadius == rhs.preBlurRadius
            && lhs.threshold == rhs.threshold
            && lhs.dilationRadius == rhs.dilationRadius
            && lhs.energyMultiplier == rhs.energyMultiplier
            && lhs.erosionRadius == rhs.erosionRadius
            && lhs.featherRadius == rhs.featherRadius
            && lhs.showRawLaplacian == rhs.showRawLaplacian
    }
}

// nonisolated(unsafe): immutable after one-time lazy init, safe to read from any context.
// Required because SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor would otherwise
// infer @MainActor on this constant, blocking access from nonisolated methods.
private nonisolated let _focusMagnitudeKernel: CIKernel? = {
    guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
          let data = try? Data(contentsOf: url)
    else {
        return nil
    }
    do {
        return try CIKernel(functionName: "focusLaplacian", fromMetalLibraryData: data)
    } catch {
        print("FocusDetector: Failed to load kernel: \(error)")
        return nil
    }
}()

@Observable
final class FocusMaskModel: @unchecked Sendable {
    // nonisolated(unsafe): FocusDetectorConfig is a struct of primitives; scoring
    // reads a snapshot while the UI disables mutation — no real concurrent write risk.
    nonisolated(unsafe) var config = FocusDetectorConfig()

    /// IMPROVEMENT 1: Force float32 working format so Laplacian
    /// intermediate values are not clipped to 8-bit before thresholding.
    /// nonisolated(unsafe): CIContext is thread-safe for concurrent renders; let never mutated.
    private nonisolated(unsafe) let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf
    ])

    /// IMPROVEMENT 4: ARW-aware entry point.
    /// Loads the raw file via CIRAWFilter with NR, sharpening and boost
    /// all disabled so the Laplacian fires on true optical sharpness.
    /// Falls back to the CGImage path if CIRAWFilter is unavailable or
    /// the URL does not point to a supported RAW format.
    func generateFocusMask(fromRawURL url: URL, scale: CGFloat) async -> CGImage? {
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            guard let rawFilter = CIRAWFilter(imageURL: url) else {
                // Not a RAW file or unsupported — fall back to decoded path

                guard let cgImage = CGImage(
                    jpegDataProviderSource: CGDataProvider(url: url as CFURL)!,
                    decode: nil, shouldInterpolate: true, intent: .defaultIntent,
                ) else { return nil }
                return Self.buildFocusMask(from: CIImage(cgImage: cgImage),
                                           scale: scale, context: context, config: config)
            }
            // Disable all in-camera processing before focus analysis
            rawFilter.luminanceNoiseReductionAmount = 0 // luma NR
            rawFilter.colorNoiseReductionAmount = 0 // chroma NR
            rawFilter.contrastAmount = 0 // contrast
            rawFilter.detailAmount = 0 // detail / micro-contrast
            rawFilter.moireReductionAmount = 0 // moire
            rawFilter.boostAmount = 0 // global tone curve
            rawFilter.boostShadowAmount = 0 // shadow lift
            rawFilter.sharpnessAmount = 0 // critical: no USM
            rawFilter.localToneMapAmount = 0 // local tone mapping
            rawFilter.isGamutMappingEnabled = false // no gamut clip
            rawFilter.isLensCorrectionEnabled = false // no lens warp

            guard let linearImage = rawFilter.outputImage else { return nil }
            return Self.buildFocusMask(from: linearImage,
                                       scale: scale, context: context, config: config)
        }.value
    }

    /// Existing NSImage entry point — unchanged public API
    func generateFocusMask(from nsImage: NSImage, scale: CGFloat) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            guard let result = Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale, context: context, config: config,
            ) else { return nil }
            return NSImage(cgImage: result, size: originalSize)
        }.value
    }

    /// Existing CGImage entry point — unchanged public API
    func generateFocusMask(from cgImage: CGImage, scale: CGFloat) async -> CGImage? {
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale, context: context, config: config,
            )
        }.value
    }

    /// Computes a scalar sharpness score for a RAW file without generating a
    /// visual mask. Extracts the embedded JPEG thumbnail from the ARW (the same
    /// data the grid view already uses) and runs it through the Laplacian pipeline.
    /// This is ~20-50× faster than a full CIRAWFilter decode and produces accurate
    /// relative scores within a burst.
    ///
    /// The returned value is in [0, ∞). Compare values *relative to each other*
    /// within the same burst — do not treat the number as an absolute measure.
    nonisolated func computeSharpnessScore(fromRawURL url: URL, thumbnailMaxPixelSize: Int = 512) -> Float? {
        let config = self.config
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize
        ]

        // Wrap ImageIO in an explicit QoS context. DispatchQueue.sync establishes
        // a libdispatch sync override that propagates .userInitiated priority to
        // any internal dispatch queues ImageIO uses, preventing priority inversion.
        let cgThumb: CGImage? = DispatchQueue.global(qos: .userInitiated).sync {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        guard let cgThumb else { return nil }

        let region = Self.salientRegion(for: cgThumb)
        return Self.computeSharpnessScalar(
            from: CIImage(cgImage: cgThumb),
            salientRegion: region,
            context: context,
            config: config,
        )
    }

    /// Runs VNGenerateAttentionBasedSaliencyImageRequest synchronously and returns
    /// the union bounding box of all salient objects in normalised Vision coordinates
    /// (origin bottom-left, values in [0, 1]). Returns nil when nothing meaningful
    /// is detected (< 3 % of image area) so the caller falls back to full-image scoring.
    ///
    /// Using salientObjects bounding boxes — rather than rendering the saliency pixel
    /// buffer through CIContext — avoids coordinate-space and value-range ambiguities
    /// while still restricting scoring to the subject region.
    private nonisolated static func salientRegion(for cgImage: CGImage) -> CGRect? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let observation = request.results?.first,
              let objects = observation.salientObjects,
              !objects.isEmpty else { return nil }
        let union = objects.reduce(CGRect.null) { $0.union($1.boundingBox) }
        guard union.width * union.height > 0.03 else { return nil }
        return union
    }

    /// Runs passes 1–3 of the focus pipeline (blur → Laplacian → amplify) then
    /// collapses to a scalar via a region-restricted 95th-percentile.
    /// `nonisolated` lets this be called synchronously from Task.detached without
    /// hopping back to the main actor.
    private nonisolated static func computeSharpnessScalar(
        from inputImage: CIImage,
        salientRegion: CGRect?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> Float? {
        // Pass 1: Gaussian pre-blur (noise suppression)
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = inputImage
        preBlur.radius = config.preBlurRadius
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // Pass 2: Metal Laplacian kernel
        guard let laplacianKernel = _focusMagnitudeKernel else { return nil }
        guard let laplacianOutput = laplacianKernel.apply(
            extent: smoothedImage.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothedImage],
        ) else { return nil }

        // Pass 3: Amplify (same multiplier as visual mask for consistent calibration)
        let boost = CIFilter.colorMatrix()
        boost.inputImage = laplacianOutput
        boost.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        boost.gVector = CIVector(x: 0, y: CGFloat(config.energyMultiplier), z: 0, w: 0)
        boost.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.energyMultiplier), w: 0)
        boost.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let boostedLaplacian = boost.outputImage else { return nil }

        // Collapse to scalar: region-restricted 95th-percentile of the red channel.
        //
        // When Vision detected a salient subject, only the Laplacian pixels inside
        // that bounding box are sorted — background texture (rocks, bokeh, sky) is
        // excluded entirely. Laplacian values are never scaled down by a weight, so
        // the score magnitude is independent of how large or small the subject is and
        // the max-normalisation in the UI remains stable. When no region is available
        // every pixel is included (same behaviour as the plain 95th-percentile path).
        //
        // Vision bounding boxes use normalised coordinates with origin at bottom-left,
        // matching the CIImage / Laplacian bitmap coordinate system (row 0 = bottom).
        let extent = boostedLaplacian.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        var laplacianPixels = [Float](repeating: 0, count: pixelCount * 4)
        context.render(
            boostedLaplacian,
            toBitmap: &laplacianPixels,
            rowBytes: width * 16,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil,
        )

        var redChannel: [Float]
        if let region = salientRegion {
            // Map normalised Vision coords → pixel indices in the Laplacian bitmap.
            let colStart = max(0, Int(region.minX * CGFloat(width)))
            let colEnd = min(width, Int(region.maxX * CGFloat(width)))
            let rowStart = max(0, Int(region.minY * CGFloat(height)))
            let rowEnd = min(height, Int(region.maxY * CGFloat(height)))

            var filtered = [Float]()
            filtered.reserveCapacity((colEnd - colStart) * (rowEnd - rowStart))
            for row in rowStart ..< rowEnd {
                for col in colStart ..< colEnd {
                    filtered.append(laplacianPixels[(row * width + col) * 4])
                }
            }
            // Fall back to full image if the mapped region turned out empty
            redChannel = filtered.isEmpty
                ? (0 ..< pixelCount).map { laplacianPixels[$0 * 4] }
                : filtered
        } else {
            redChannel = (0 ..< pixelCount).map { laplacianPixels[$0 * 4] }
        }

        // Sort ascending and return 95th percentile.
        redChannel.sort()
        let idx = min(Int(Float(redChannel.count) * 0.95), redChannel.count - 1)
        return redChannel[idx]
    }

    /// IMPROVEMENT 5: Single unified implementation — both public overloads
    /// delegate here, eliminating the previous code duplication.
    private nonisolated static func buildFocusMask(
        from inputImage: CIImage,
        scale: CGFloat,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale),
        )

        // Pass 1: Gaussian pre-blur (noise suppression)
        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = scaledImage
        preBlur.radius = config.preBlurRadius
        guard let smoothedImage = preBlur.outputImage else { return nil }

        // Pass 2: Laplacian (custom Metal kernel)
        guard let laplacianKernel = _focusMagnitudeKernel else { return nil }
        guard let laplacianOutput = laplacianKernel.apply(
            extent: smoothedImage.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothedImage],
        ) else { return nil }

        // IMPROVEMENT 3: Amplify BEFORE threshold so the threshold operates
        // on a boosted signal. The energyMultiplier now affects mask quality,
        // not just overlay brightness.
        let preThresholdBoost = CIFilter.colorMatrix()
        preThresholdBoost.inputImage = laplacianOutput
        preThresholdBoost.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        preThresholdBoost.gVector = CIVector(x: 0, y: CGFloat(config.energyMultiplier), z: 0, w: 0)
        preThresholdBoost.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.energyMultiplier), w: 0)
        preThresholdBoost.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        guard let boostedLaplacian = preThresholdBoost.outputImage else { return nil }

        // Debug shortcut: skip threshold/morphology and return the raw
        // Laplacian response directly so preBlurRadius and energyMultiplier
        // can be calibrated visually before touching the other controls.
        if config.showRawLaplacian {
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return context.createCGImage(cropped, from: cropped.extent)
        }

        // Pass 3: Threshold on the boosted signal
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = boostedLaplacian
        thresholdFilter.threshold = config.threshold
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // Pass 4a: Optional erosion — removes isolated noise pixels that
        // survive thresholding before the dilation widens them.
        let eroded: CIImage
        if config.erosionRadius > 0,
           let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            erode.setValue(CGFloat(config.erosionRadius), forKey: kCIInputRadiusKey)
            eroded = erode.outputImage ?? thresholdedEdges
        } else {
            eroded = thresholdedEdges
        }

        // Pass 4b: Dilation — fills small gaps and connects nearby blobs.
        let dilated: CIImage
        if config.dilationRadius > 0,
           let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(eroded, forKey: kCIInputImageKey)
            dilate.setValue(CGFloat(config.dilationRadius), forKey: kCIInputRadiusKey)
            dilated = dilate.outputImage ?? eroded
        } else {
            dilated = eroded
        }

        // Pass 5: Map to red channel for visual overlay
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        // Pass 6: Optional feather — final Gaussian for soft mask edges.
        let feathered: CIImage
        if config.featherRadius > 0 {
            let featherBlur = CIFilter.gaussianBlur()
            featherBlur.inputImage = redMask
            featherBlur.radius = config.featherRadius
            feathered = featherBlur.outputImage ?? redMask
        } else {
            feathered = redMask
        }

        let croppedMask = feathered.cropped(to: scaledImage.extent)
        return context.createCGImage(croppedMask, from: croppedMask.extent)
    }
}
