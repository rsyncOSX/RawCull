import Accelerate
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Observation
import OSLog
import Vision

/// Saliency detection result: whether a salient region was found and, if Vision
/// classification succeeded, what the dominant subject is.
struct SaliencyInfo {
    /// Top VNClassifyImageRequest label with confidence ≥ 0.20, nil if none found.
    let subjectLabel: String?
}

struct FocusDetectorConfig {
    var preBlurRadius: Float = 1.92
    /// ISO at capture time. Used to scale preBlurRadius upward at high ISO
    /// where noise would otherwise cause the Laplacian to fire on noise rather
    /// than real edges. Default 400 (no adaptation).
    var iso: Int = 400
    var threshold: Float = 0.46
    var dilationRadius: Float = 1.0
    var energyMultiplier: Float = 7.62
    var erosionRadius: Float = 1.0
    var featherRadius: Float = 2.0
    var showRawLaplacian: Bool = false

    // MARK: Scoring-only parameters (do not affect the focus mask overlay)

    /// Fraction of image dimension excluded from each border when computing
    /// the full-frame sharpness score. Prevents Gaussian-blur edge artifacts
    /// from inflating the score. Range 0–0.10.
    var borderInsetFraction: Float = 0.04

    /// Weight given to the salient-region score vs the full-frame score.
    /// 0 = full-frame only, 1 = subject region only.
    var salientWeight: Float = 0.75

    /// Bonus multiplier for subject size.
    var subjectSizeFactor: Float = 0.1

    /// When true, runs VNClassifyImageRequest alongside saliency detection.
    var enableSubjectClassification: Bool = true

    /// Half-size of the AF-point scoring region as a fraction of image dimension.
    var afRegionRadius: Float = 0.12
}

// Explicit nonisolated conformance so the @Observable macro's change-tracking
// code can call == from a nonisolated context.
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
            && lhs.borderInsetFraction == rhs.borderInsetFraction
            && lhs.salientWeight == rhs.salientWeight
            && lhs.subjectSizeFactor == rhs.subjectSizeFactor
            && lhs.enableSubjectClassification == rhs.enableSubjectClassification
            && lhs.afRegionRadius == rhs.afRegionRadius
    }
}

extension FocusDetectorConfig {
    /// Birds-in-flight preset.
    static var birdsInFlight: FocusDetectorConfig {
        var c = FocusDetectorConfig()
        c.preBlurRadius = 2.2
        c.threshold = 0.46
        c.dilationRadius = 1.0
        c.erosionRadius = 1.0
        c.featherRadius = 2.0

        c.borderInsetFraction = 0.05
        c.salientWeight = 0.85
        c.subjectSizeFactor = 0.05
        c.enableSubjectClassification = true
        c.afRegionRadius = 0.06
        return c
    }

    /// Perched/static wildlife preset.
    static var perchedWildlife: FocusDetectorConfig {
        var c = FocusDetectorConfig()
        c.preBlurRadius = 1.8
        c.threshold = 0.44
        c.dilationRadius = 1.0
        c.erosionRadius = 1.0
        c.featherRadius = 1.5

        c.borderInsetFraction = 0.04
        c.salientWeight = 0.70
        c.subjectSizeFactor = 0.08
        c.enableSubjectClassification = true
        c.afRegionRadius = 0.08
        return c
    }
}

private nonisolated let _focusMagnitudeKernel: CIKernel? = {
    guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
          let data = try? Data(contentsOf: url)
    else { return nil }

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
                config: config
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
                config: config
            )
        }.value
    }

    nonisolated func computeSharpnessScore(
        fromRawURL url: URL,
        config: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        afPoint: CGPoint? = nil
    ) async -> (score: Float?, saliency: SaliencyInfo?) {
        return await Task.detached(priority: .userInitiated) { [context] in
            let binaryImg = Self.decodeBinaryFallback(at: url, maxPixelSize: thumbnailMaxPixelSize)

            let cgImage: CGImage
            if let img = binaryImg {
                cgImage = img
            } else {
                guard let img = Self.decodeThumbnail(at: url, maxPixelSize: thumbnailMaxPixelSize) else {
                    return (nil, nil)
                }
                cgImage = img
            }

            let (region, saliencyInfo) = Self.detectSaliencyAndClassify(
                for: cgImage, classify: config.enableSubjectClassification)
            let score = Self.computeSharpnessScalar(
                from: CIImage(cgImage: cgImage),
                salientRegion: region,
                afPoint: afPoint,
                context: context,
                config: config
            )
            return (score, saliencyInfo)
        }.value
    }

    // MARK: - Decode helpers

    private nonisolated static func decodeImage(at url: URL) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }

        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceShouldAllowFloat: true
        ]
        return CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary)
    }

    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    /// Binary fallback for ARW 6.0 (RA16) files where CGImageSourceCreateThumbnailAtIndex
    /// returns nil. Reads the embedded JPEG directly from the file bytes via
    /// SonyMakerNoteParser, bypassing the RA16 decoder entirely.
    private nonisolated static func decodeBinaryFallback(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let raw = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }

        return Self.normalizeToSRGB(raw)
    }

    /// Re-renders a CGImage through an 8-bit sRGB RGBA CGContext so that the Metal
    /// pipeline always receives a predictable pixel format, regardless of the
    /// source JPEG's color space or bit depth.
    private nonisolated static func normalizeToSRGB(_ image: CGImage) -> CGImage? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return image }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(
            data: nil,
            width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: bitmapInfo.rawValue
        ) else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    // MARK: - Saliency

    private nonisolated static func detectSaliencyAndClassify(for cgImage: CGImage, classify: Bool) -> (region: CGRect?, saliency: SaliencyInfo?) {
        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let classifyRequest = VNClassifyImageRequest()
        let requests: [VNRequest] = classify ? [saliencyRequest, classifyRequest] : [saliencyRequest]
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform(requests)

        guard let observation = saliencyRequest.results?.first,
              let objects = observation.salientObjects,
              !objects.isEmpty else { return (nil, nil) }

        let union = objects.reduce(CGRect.null) { $0.union($1.boundingBox) }
        let maxConfidence = objects.map(\.confidence).max() ?? 0
        guard union.width * union.height > 0.03 || maxConfidence >= 0.9 else { return (nil, nil) }

        let label = Self.bestClassificationLabel(from: classifyRequest.results ?? [])
        return (union, SaliencyInfo(subjectLabel: label))
    }

    private nonisolated static func bestClassificationLabel(from observations: [VNClassificationObservation]) -> String? {
        guard !observations.isEmpty else { return nil }

        let subjectKeywords = [
            "bird", "raptor", "fowl", "waterfowl", "wildlife",
            "animal", "mammal", "vertebrate", "creature", "predator",
            "reptile", "amphibian", "insect", "spider",
            "dog", "cat", "horse", "deer", "bear", "fox", "wolf",
            "lion", "tiger", "elephant", "monkey", "ape",
            "person", "people", "human", "face", "portrait"
        ]

        let environmentTokens = [
            "structure", "plant", "grass", "tree", "forest", "wood",
            "nature", "outdoor", "indoor", "landscape", "sky", "water",
            "ground", "soil", "rock", "stone", "darkness", "light",
            "photography", "scene", "background", "texture", "pattern"
        ]

        for obs in observations where obs.confidence >= 0.06 {
            let id = obs.identifier.lowercased()
            if subjectKeywords.contains(where: { id.contains($0) }) {
                return obs.identifier.replacingOccurrences(of: "_", with: " ")
            }
        }

        for obs in observations where obs.confidence >= 0.15 {
            let id = obs.identifier.lowercased()
            if !environmentTokens.contains(where: { id.contains($0) }) {
                return obs.identifier.replacingOccurrences(of: "_", with: " ")
            }
        }

        return nil
    }

    // MARK: - Numeric helpers

    /// p90–p97 band mean relative to the p20 noise floor, penalized when fewer
    /// than 6% of pixels land in the band (sparse edges → likely out-of-focus).
    nonisolated static func robustTailScore(_ samples: [Float]) -> Float? {
        guard !samples.isEmpty else { return nil }
        var a = samples
        let n = a.count

        // Accelerate SIMD sort: O(n log n), no worst-case O(n²) for equal-value inputs.
        // The previous quickselect with median-of-one pivot was O(n²) when the Laplacian
        // output is heavily zero-biased (blurry/out-of-focus images at high ISO).
        vDSP.sort(&a, sortOrder: .ascending)

        func p(_ frac: Float) -> Float {
            a[min(max(Int(Float(n - 1) * frac), 0), n - 1)]
        }

        let p20 = p(0.20)
        let p90 = p(0.90)
        let p97 = p(0.97)

        if p97 <= p90 { return max(0, p90 - p20) }

        var sum: Float = 0
        var cnt = 0
        for v in samples where v >= p90 && v <= p97 {
            sum += max(0, v - p20)
            cnt += 1
        }
        guard cnt > 0 else { return max(0, p90 - p20) }

        let bandMean = sum / Float(cnt)
        let densityFactor = min(1.0, (Float(cnt) / Float(n)) / 0.06)

        return bandMean * densityFactor
    }

    /// Standard deviation of Laplacian sample values.
    /// Near zero for blurry/smooth regions; higher for real textured detail.
    nonisolated static func microContrast(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        var sum2: Float = 0
        var n: Float = 0
        for v in samples where v.isFinite {
            sum += v
            sum2 += v * v
            n += 1
        }
        guard n > 1 else { return 0 }
        let mean = sum / n
        return sqrt(max(0, (sum2 / n) - mean * mean))
    }

    // MARK: - Scalar scoring

    private nonisolated static func computeSharpnessScalar(
        from inputImage: CIImage,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        context: CIContext,
        config: FocusDetectorConfig
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
            colorSpace: nil
        )

        @inline(__always)
        func redAt(_ idx: Int) -> Float { rgba[idx * 4] }

        // Exclude outer border to avoid Gaussian edge artifacts
        let borderCols = max(0, Int(Float(width) * config.borderInsetFraction))
        let borderRows = max(0, Int(Float(height) * config.borderInsetFraction))
        let innerW = max(0, width - 2 * borderCols)
        let innerH = max(0, height - 2 * borderRows)

        var full = [Float]()
        full.reserveCapacity(innerW * innerH)
        for row in borderRows ..< (height - borderRows) {
            let base = row * width
            for col in borderCols ..< (width - borderCols) {
                let v = redAt(base + col)
                if v.isFinite { full.append(v) }
            }
        }

        // Single-pass region analysis: pixel samples + silhouette fraction together.
        struct RegionAnalysis {
            let samples: [Float]
            let borderFraction: Float  // border energy / total; high => silhouette-dominated
        }

        func analyzeRegion(_ region: CGRect) -> RegionAnalysis {
            let colStart = max(0, Int(region.minX * CGFloat(width)))
            let colEnd = min(width, Int(region.maxX * CGFloat(width)))
            // Vision uses y=0 at the visual bottom; CIImage(cgImage:) flips to top-left
            // origin, so context.render fills row 0 at the visual top. Invert y so we
            // sample the region Vision identified. Removing this flip silently scores
            // the wrong area.
            let rowStart = max(0, Int((1.0 - region.maxY) * CGFloat(height)))
            let rowEnd = min(height, Int((1.0 - region.minY) * CGFloat(height)))

            guard colEnd > colStart, rowEnd > rowStart else {
                return RegionAnalysis(samples: [], borderFraction: 1.0)
            }

            let rw = colEnd - colStart
            let rh = rowEnd - rowStart
            let b = max(1, Int(0.12 * Float(min(rw, rh))))

            var samples = [Float]()
            samples.reserveCapacity(rw * rh)
            var borderSum: Float = 0
            var borderCnt = 0
            var innerSum: Float = 0
            var innerCnt = 0

            for row in rowStart ..< rowEnd {
                let base = row * width
                for col in colStart ..< colEnd {
                    let v = redAt(base + col)
                    guard v.isFinite else { continue }
                    samples.append(v)

                    let isBorder =
                        (col - colStart) < b || (colEnd - 1 - col) < b ||
                        (row - rowStart) < b || (rowEnd - 1 - row) < b

                    if isBorder {
                        borderSum += v
                        borderCnt += 1
                    } else {
                        innerSum += v
                        innerCnt += 1
                    }
                }
            }

            let borderFraction: Float
            if borderCnt > 0, innerCnt > 0 {
                let bm = borderSum / Float(borderCnt)
                let im = innerSum / Float(innerCnt)
                borderFraction = bm / max(bm + im, 1e-6)
            } else {
                borderFraction = 1.0
            }

            return RegionAnalysis(samples: samples, borderFraction: borderFraction)
        }

        let fullScore = Self.robustTailScore(full)

        var salientAnalysis: RegionAnalysis?
        var salientScore: Float?
        if let region = salientRegion {
            let a = analyzeRegion(region)
            salientAnalysis = a
            if a.samples.count >= 256 { salientScore = Self.robustTailScore(a.samples) }
        }

        // AF-point subject score
        var afAnalysis: RegionAnalysis?
        var afScore: Float?
        var afRegionUsed: CGRect?
        if let pt = afPoint, config.afRegionRadius > 0 {
            let r = CGFloat(config.afRegionRadius)
            let visionY = 1.0 - pt.y
            let afRegionRaw = CGRect(x: pt.x - r, y: visionY - r, width: r * 2, height: r * 2)
            let afRegion = afRegionRaw.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            if !afRegion.isNull, !afRegion.isEmpty {
                let a = analyzeRegion(afRegion)
                if a.samples.count >= 64 {
                    afScore = Self.robustTailScore(a.samples)
                    afRegionUsed = afRegion
                    afAnalysis = a
                }
            }
        }

        let effectiveSubjectScore = afScore ?? salientScore
        let effectiveAnalysis = afAnalysis ?? salientAnalysis

        // HARD BLUR GATE: if subject micro-detail is too low, clamp score down
        let subjectMicro = effectiveAnalysis.map { Self.microContrast($0.samples) } ?? 0
        let blurGate: Float = 0.014
        if let ea = effectiveAnalysis, ea.samples.count >= 64, subjectMicro < blurGate {
            return max(0.01, (effectiveSubjectScore ?? fullScore ?? 0) * 0.12)
        }

        switch (fullScore, effectiveSubjectScore) {
        case let (f?, s?):
            let w = config.salientWeight
            var blended = f * (1.0 - w) + s * w

            // Silhouette penalty
            if let ea = effectiveAnalysis {
                let frac = ea.borderFraction
                let t: Float = 0.62
                if frac > t {
                    let over = min(1.0, (frac - t) / (1.0 - t))
                    blended *= 1.0 - 0.55 * over
                }
            }

            // Subject-size bonus only for Vision saliency region (not AF)
            if afRegionUsed == nil, let region = salientRegion {
                let area = Float(region.width * region.height)
                blended *= 1.0 + area * config.subjectSizeFactor
            }

            return blended

        case let (f?, nil):
            let p = (1.0 - config.salientWeight)
            return f * p * p * p

        case let (nil, s?):
            return s

        default:
            return nil
        }
    }

    // MARK: - Mask generation

    private nonisolated static func buildAmplifiedLaplacian(from image: CIImage, config: FocusDetectorConfig) -> CIImage? {
        let isoFactor = max(1.0, min(sqrt(Float(max(config.iso, 1)) / 400.0), 3.0))
        let imageWidth = Float(image.extent.width)
        let resFactor = max(1.0, min(sqrt(max(imageWidth, 512.0) / 512.0), 3.0))
        let effectiveRadius = min(config.preBlurRadius * isoFactor * resFactor, 100.0)

        let preBlur = CIFilter.gaussianBlur()
        preBlur.inputImage = image
        preBlur.radius = effectiveRadius
        guard let smoothed = preBlur.outputImage else { return nil }

        guard let kernel = _focusMagnitudeKernel else { return nil }
        guard let laplacianOutput = kernel.apply(
            extent: smoothed.extent.insetBy(dx: 1, dy: 1),
            roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
            arguments: [smoothed]
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
        config: FocusDetectorConfig
    ) -> CGImage? {
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let rawLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: config) else { return nil }

        let boostedLaplacian: CIImage
        if config.borderInsetFraction > 0 {
            let ext = scaledImage.extent
            let borderX = ext.width * CGFloat(config.borderInsetFraction)
            let borderY = ext.height * CGFloat(config.borderInsetFraction)
            let innerRect = ext.insetBy(dx: borderX, dy: borderY)
            let blackBg = CIImage(color: .black).cropped(to: ext)
            boostedLaplacian = rawLaplacian.cropped(to: innerRect).composited(over: blackBg)
        } else {
            boostedLaplacian = rawLaplacian
        }

        if config.showRawLaplacian {
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return context.createCGImage(cropped, from: cropped.extent)
        }

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = boostedLaplacian
        thresholdFilter.threshold = config.threshold
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        let erosionPx = Self.morphologyPixelRadius(config.erosionRadius)
        let eroded: CIImage
        if erosionPx > 0, let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            erode.setValue(erosionPx, forKey: kCIInputRadiusKey)
            eroded = erode.outputImage ?? thresholdedEdges
        } else {
            eroded = thresholdedEdges
        }

        let dilationPx = Self.morphologyPixelRadius(config.dilationRadius)
        let dilated: CIImage
        if dilationPx > 0, let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(eroded, forKey: kCIInputImageKey)
            dilate.setValue(dilationPx, forKey: kCIInputRadiusKey)
            dilated = dilate.outputImage ?? eroded
        } else {
            dilated = eroded
        }

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = dilated
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else { return nil }

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

    @MainActor
    func applyCalibration(_ result: FocusCalibrationResult) {
        var cfg = config
        cfg.threshold = result.threshold
        cfg.energyMultiplier = result.energyMultiplier
        config = cfg
    }

    @MainActor
    func calibrateAndApplyFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        thumbnailMaxPixelSize: Int = 512,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8
    ) async -> FocusCalibrationResult? {
        let base = config
        guard let result = await calibrateFromBurstParallel(
            files: files,
            baseConfig: base,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            thresholdPercentile: thresholdPercentile,
            targetP95AfterGain: targetP95AfterGain,
            minSamples: minSamples,
            maxConcurrentTasks: maxConcurrentTasks
        ) else { return nil }

        applyCalibration(result)
        return result
    }

    nonisolated func calibrateFromBurstParallel(
        files: [(url: URL, iso: Int?)],
        baseConfig: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8
    ) async -> FocusCalibrationResult? {
        guard !files.isEmpty else { return nil }

        let tSize = thumbnailMaxPixelSize
        let concurrency = max(1, min(maxConcurrentTasks, files.count))

        var nextIndex = 0
        var scores = [Float]()
        scores.reserveCapacity(files.count)

        await withTaskGroup(of: Float?.self) { group in
            for _ in 0 ..< concurrency {
                guard nextIndex < files.count else { break }
                let entry = files[nextIndex]
                nextIndex += 1

                group.addTask { [baseConfig, tSize] in
                    var fileConfig = baseConfig
                    fileConfig.energyMultiplier = 1.0
                    fileConfig.iso = entry.iso ?? 400
                    fileConfig.enableSubjectClassification = false
                    let result = await self.computeSharpnessScore(
                        fromRawURL: entry.url,
                        config: fileConfig,
                        thumbnailMaxPixelSize: tSize
                    )
                    return result.score
                }
            }

            while let value = await group.next() {
                if let s = value, s.isFinite, s > 0 { scores.append(s) }

                if nextIndex < files.count {
                    let entry = files[nextIndex]
                    nextIndex += 1

                    group.addTask { [baseConfig, tSize] in
                        var fileConfig = baseConfig
                        fileConfig.energyMultiplier = 1.0
                        fileConfig.iso = entry.iso ?? 400
                        fileConfig.enableSubjectClassification = false
                        let result = await self.computeSharpnessScore(
                            fromRawURL: entry.url,
                            config: fileConfig,
                            thumbnailMaxPixelSize: tSize
                        )
                        return result.score
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
        let tunedThreshold = min(percentile(scores, thresholdPercentile) * tunedGain, 1.0)

        return FocusCalibrationResult(
            threshold: tunedThreshold,
            energyMultiplier: tunedGain,
            sampleCount: scores.count,
            p50: p50,
            p90: p90,
            p95: p95,
            p99: p99
        )
    }
}
