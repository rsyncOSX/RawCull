import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Observation
import OSLog
import Vision

struct FocusDetectorConfig {
    var preBlurRadius: Float = 1.92
    /// ISO at capture time. Used to scale preBlurRadius upward at high ISO
    /// where noise would otherwise cause the Laplacian to fire on noise rather
    /// than real edges. Default 400 (no adaptation).
    var iso: Int = 400
    var threshold: Float = 0.46
    var dilationRadius: Float = 1.0 // was 0.43
    var energyMultiplier: Float = 7.62
    var erosionRadius: Float = 1.0 // was 0.27
    var featherRadius: Float = 2.0
    var showRawLaplacian: Bool = false
}

// Explicit nonisolated conformance so the @Observable macro's change-tracking
// code can call == from a nonisolated context.
// SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor would make the synthesized == @MainActor,
// blocking the nonisolated call site — so we must spell it out manually.
// swiftformat:disable:next redundantEquatable
extension FocusDetectorConfig: Equatable {
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.preBlurRadius == rhs.preBlurRadius
            && lhs.iso == rhs.iso
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
        Logger.process.debugMessageOnly("FocusDetector: Failed to load kernel: \(error)")
        return nil
    }
}()

@Observable
final class FocusMaskModel: @unchecked Sendable {
    var config = FocusDetectorConfig()

    /// Force float32 working format so Laplacian intermediate values are not clipped.
    /// nonisolated(unsafe): CIContext is thread-safe for concurrent renders; let never mutated.
    private nonisolated let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf
    ])

    // MARK: - Public API

    func generateFocusMask(from nsImage: NSImage, scale: CGFloat) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            guard let result = Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale,
                context: context,
                config: config,
            ) else { return nil }
            return NSImage(cgImage: result, size: originalSize)
        }.value
    }

    func generateFocusMask(from cgImage: CGImage, scale: CGFloat) async -> CGImage? {
        let context = self.context
        let config = self.config

        return await Task.detached(priority: .userInitiated) {
            Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale,
                context: context,
                config: config,
            )
        }.value
    }

    /// Computes scalar sharpness from fast thumbnail path, with full-decode fallback.
    /// Returned value is relative; compare within same burst/session.
    nonisolated func computeSharpnessScore(
        fromRawURL url: URL,
        config: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
    ) async -> Float? {
        let cgImage: CGImage? = await Task.detached(priority: .userInitiated) {
            Self.decodeThumbnail(at: url, maxPixelSize: thumbnailMaxPixelSize)
                ?? Self.decodeImage(at: url)
        }.value

        guard let cgImage else { return nil }

        let region = Self.salientRegion(for: cgImage)
        return Self.computeSharpnessScalar(
            from: CIImage(cgImage: cgImage),
            salientRegion: region,
            context: context,
            config: config,
        )
    }

    // MARK: - Decode helpers

    /// Safe, format-agnostic first-frame decode.
    private nonisolated static func decodeImage(at url: URL) -> CGImage? {
        let srcOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }

        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary)
    }

    /// Fast thumbnail decode: uses embedded thumbnail when present.
    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else {
            return nil
        }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    // MARK: - Saliency

    /// Returns union bounding box of salient objects in normalized Vision coords.
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

    // MARK: - Scalar scoring

    /// Robust scalar sharpness:
    /// blur -> Laplacian -> amplify -> robust tail score.
    /// Computes both full-frame and salient-region score, then fuses conservatively.
    private nonisolated static func computeSharpnessScalar(
        from inputImage: CIImage,
        salientRegion: CGRect?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> Float? {
        guard let boosted = buildAmplifiedLaplacian(from: inputImage, config: config) else { return nil }

        let extent = boosted.extent
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        let pixelCount = width * height
        var rgba = [Float](repeating: 0, count: pixelCount * 4)
        context.render(
            boosted,
            toBitmap: &rgba,
            rowBytes: width * 16,
            bounds: extent,
            format: .RGBAf,
            colorSpace: nil,
        )

        @inline(__always)
        func redAt(_ idx: Int) -> Float {
            rgba[idx * 4]
        }

        var full = [Float]()
        full.reserveCapacity(pixelCount)
        for i in 0 ..< pixelCount {
            let v = redAt(i)
            if v.isFinite { full.append(v) }
        }

        func regionSamples(_ region: CGRect) -> [Float] {
            let colStart = max(0, Int(region.minX * CGFloat(width)))
            let colEnd = min(width, Int(region.maxX * CGFloat(width)))
            let rowStart = max(0, Int(region.minY * CGFloat(height)))
            let rowEnd = min(height, Int(region.maxY * CGFloat(height)))

            guard colEnd > colStart, rowEnd > rowStart else { return [] }

            var out = [Float]()
            out.reserveCapacity((colEnd - colStart) * (rowEnd - rowStart))
            for row in rowStart ..< rowEnd {
                let base = row * width
                for col in colStart ..< colEnd {
                    let v = redAt(base + col)
                    if v.isFinite { out.append(v) }
                }
            }
            return out
        }

        @inline(__always)
        func partition(_ a: inout [Float], _ lo: Int, _ hi: Int, _ p: Int) -> Int {
            let pivot = a[p]
            a.swapAt(p, hi)
            var store = lo
            for i in lo ..< hi where a[i] < pivot {
                a.swapAt(store, i)
                store += 1
            }
            a.swapAt(store, hi)
            return store
        }

        func quickselect(_ a: inout [Float], k: Int) -> Float {
            var lo = 0
            var hi = a.count - 1
            while true {
                if lo == hi { return a[lo] }
                let pivotIndex = (lo + hi) >> 1
                let p = partition(&a, lo, hi, pivotIndex)
                if k == p { return a[k] }
                if k < p { hi = p - 1 } else { lo = p + 1 }
            }
        }

        /// Score as winsorized tail mean (>= p95, clipped at p99.5)
        func robustTailScore(_ samples: [Float]) -> Float? {
            guard !samples.isEmpty else { return nil }
            var a = samples
            let n = a.count

            let k95 = min(max(Int(Float(n) * 0.95), 0), n - 1)
            let k995 = min(max(Int(Float(n) * 0.995), 0), n - 1)

            let p95 = quickselect(&a, k: k95)
            let p995 = quickselect(&a, k: k995)

            var sum: Float = 0
            var cnt = 0
            for v in samples where v >= p95 {
                sum += min(v, p995)
                cnt += 1
            }
            guard cnt > 0 else { return p95 }
            return sum / Float(cnt)
        }

        let fullScore = robustTailScore(full)

        var salientScore: Float?
        if let region = salientRegion {
            let s = regionSamples(region)
            if s.count >= 256 {
                salientScore = robustTailScore(s)
            }
        }

        // Conservative fusion to avoid saliency failures collapsing score.
        switch (fullScore, salientScore) {
        case let (f?, s?):
            return max(f * 0.85, s * 0.90)

        case let (f?, nil):
            return f

        case let (nil, s?):
            return s

        default:
            return nil
        }
    }

    // MARK: - Mask generation

    /// Shared passes 1–3: blur → Laplacian → amplify.
    /// Used by both scalar scoring and mask generation so tuning one affects both.
    ///
    /// The Gaussian pre-blur radius is scaled dynamically:
    /// - ISO adaptation: noise amplitude ∝ √(ISO/400); higher ISO needs more blur
    ///   to suppress noise before the Laplacian fires on it. Capped at 3× base.
    /// - Resolution adaptation: maintains proportional spatial-frequency cutoff
    ///   relative to the 512 px thumbnail baseline. Uses √ scaling to be
    ///   conservative. Scoring thumbnails (≈512 px) see factor ≈1.0; larger
    ///   images (e.g. 1024 px mask path) see factor ≈1.4. Capped at 3×.
    private nonisolated static func buildAmplifiedLaplacian(
        from image: CIImage,
        config: FocusDetectorConfig,
    ) -> CIImage? {
        let isoFactor = max(1.0, min(sqrt(Float(max(config.iso, 1)) / 400.0), 3.0))
        let imageWidth = Float(image.extent.width)
        let resFactor = max(1.0, min(sqrt(max(imageWidth, 512.0) / 512.0), 3.0))
        let effectiveRadius = config.preBlurRadius * isoFactor * resFactor

        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = image
        preBlur.radius = effectiveRadius
        guard let smoothed = preBlur.outputImage else { return nil }

        guard let kernel = _focusMagnitudeKernel else { return nil }
        guard let laplacianOutput = kernel.apply(
            extent: smoothed.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothed],
        ) else { return nil }

        let boost = CIFilter.colorMatrix()
        boost.inputImage = laplacianOutput
        boost.rVector = CIVector(x: CGFloat(config.energyMultiplier), y: 0, z: 0, w: 0)
        boost.gVector = CIVector(x: 0, y: CGFloat(config.energyMultiplier), z: 0, w: 0)
        boost.bVector = CIVector(x: 0, y: 0, z: CGFloat(config.energyMultiplier), w: 0)
        boost.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        return boost.outputImage
    }

    private nonisolated static func buildFocusMask(
        from inputImage: CIImage,
        scale: CGFloat,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(
            by: CGAffineTransform(scaleX: scale, y: scale),
        )

        guard let boostedLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: config) else { return nil }

        if config.showRawLaplacian {
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return context.createCGImage(cropped, from: cropped.extent)
        }

        // Pass 3: Threshold
        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = boostedLaplacian
        thresholdFilter.threshold = config.threshold
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        // Pass 4a: Optional erosion
        let erosionPx = Self.morphologyPixelRadius(config.erosionRadius)
        let eroded: CIImage
        if erosionPx > 0, let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            erode.setValue(erosionPx, forKey: kCIInputRadiusKey) // Int pixel radius
            eroded = erode.outputImage ?? thresholdedEdges
        } else {
            eroded = thresholdedEdges
        }

        // Pass 4b: Dilation
        let dilationPx = Self.morphologyPixelRadius(config.dilationRadius)
        let dilated: CIImage
        if dilationPx > 0, let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(eroded, forKey: kCIInputImageKey)
            dilate.setValue(dilationPx, forKey: kCIInputRadiusKey) // Int pixel radius
            dilated = dilate.outputImage ?? eroded
        } else {
            dilated = eroded
        }

        // Pass 5: Map to red channel
        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

        // Pass 6: Optional feather
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

    @inline(__always)
    private nonisolated static func morphologyPixelRadius(_ r: Float) -> Int {
        // Quantize to nearest pixel so morphology behaves predictably.
        // 0 disables the pass.
        max(0, Int(r.rounded()))
    }
}

extension FocusMaskModel {
    struct FocusCalibrationResult {
        let threshold: Float
        let energyMultiplier: Float
        let sampleCount: Int
        let p50: Float
        let p90: Float
        let p95: Float
        let p99: Float
    }

    /// Applies a calibration result to the current model config.
    /// Only threshold + energyMultiplier are changed.
    @MainActor
    func applyCalibration(_ result: FocusCalibrationResult) {
        var cfg = config
        cfg.threshold = result.threshold
        cfg.energyMultiplier = result.energyMultiplier
        config = cfg
    }

    /// Convenience: calibrate in parallel and immediately apply to model config.
    /// Returns calibration details for logging/UI.
    /// `files` pairs each URL with its EXIF ISO value (nil → 400 default).
    @MainActor
    func calibrateAndApplyFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        thumbnailMaxPixelSize: Int = 512,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        let base = config
        guard let result = await calibrateFromBurstParallel(
            files: files,
            baseConfig: base,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            thresholdPercentile: thresholdPercentile,
            targetP95AfterGain: targetP95AfterGain,
            minSamples: minSamples,
            maxConcurrentTasks: maxConcurrentTasks,
        ) else {
            return nil
        }

        applyCalibration(result)
        return result
    }

    /// Parallel auto-calibration for larger bursts.
    /// Limits in-flight work to avoid oversubscribing CPU/IO.
    /// Per-file ISO values are used so the adaptive pre-blur radius during
    /// calibration matches what scoring will use for each image.
    nonisolated func calibrateFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        baseConfig: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        guard !files.isEmpty else { return nil }

        let ctx = self.context
        let tSize = thumbnailMaxPixelSize
        let concurrency = max(1, min(maxConcurrentTasks, files.count))

        var nextIndex = 0
        var scores = [Float]()
        scores.reserveCapacity(files.count)

        await withTaskGroup(of: Float?.self) { group in
            // Seed initial tasks
            for _ in 0 ..< concurrency {
                guard nextIndex < files.count else { break }
                let entry = files[nextIndex]
                nextIndex += 1

                group.addTask { [baseConfig, ctx, tSize] in
                    var fileConfig = baseConfig
                    fileConfig.energyMultiplier = 1.0
                    fileConfig.iso = entry.iso ?? 400
                    guard let cgImage = Self.decodeThumbnail(at: entry.url, maxPixelSize: tSize) ?? Self.decodeImage(at: entry.url) else {
                        return nil
                    }
                    let region = Self.salientRegion(for: cgImage)
                    return Self.computeSharpnessScalar(
                        from: CIImage(cgImage: cgImage),
                        salientRegion: region,
                        context: ctx,
                        config: fileConfig,
                    )
                }
            }

            // Refill as tasks complete
            while let value = await group.next() {
                if let s = value, s.isFinite, s > 0 {
                    scores.append(s)
                }

                if nextIndex < files.count {
                    let entry = files[nextIndex]
                    nextIndex += 1

                    group.addTask { [baseConfig, ctx, tSize] in
                        var fileConfig = baseConfig
                        fileConfig.energyMultiplier = 1.0
                        fileConfig.iso = entry.iso ?? 400
                        guard let cgImage = Self.decodeThumbnail(at: entry.url, maxPixelSize: tSize) ?? Self.decodeImage(at: entry.url) else {
                            return nil
                        }
                        let region = Self.salientRegion(for: cgImage)
                        return Self.computeSharpnessScalar(
                            from: CIImage(cgImage: cgImage),
                            salientRegion: region,
                            context: ctx,
                            config: fileConfig,
                        )
                    }
                }
            }
        }

        guard scores.count >= minSamples else { return nil }
        scores.sort()

        @inline(__always)
        func percentile(_ sorted: [Float], _ p: Float) -> Float {
            let clamped = min(max(p, 0), 1)
            let idx = Int((Float(sorted.count - 1) * clamped).rounded(.toNearestOrEven))
            return sorted[idx]
        }

        let p50 = percentile(scores, 0.50)
        let p90 = percentile(scores, 0.90)
        let p95 = percentile(scores, 0.95)
        let p99 = percentile(scores, 0.99)

        let eps: Float = 1e-6
        let rawGain = targetP95AfterGain / max(p95, eps)
        let tunedGain = min(max(rawGain, 0.5), 32.0)
        // Scale threshold into the boosted space so it aligns with what
        // buildFocusMask sees after applying energyMultiplier.
        let tunedThreshold = min(percentile(scores, thresholdPercentile) * tunedGain, 1.0)

        return FocusCalibrationResult(
            threshold: tunedThreshold,
            energyMultiplier: tunedGain,
            sampleCount: scores.count,
            p50: p50,
            p90: p90,
            p95: p95,
            p99: p99,
        )
    }
}
