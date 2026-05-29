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
struct SaliencyInfo: Codable, Equatable {
    /// Top VNClassifyImageRequest label with confidence ≥ 0.20, nil if none found.
    let subjectLabel: String?
    /// Highest confidence reported by Vision's salient-object observations.
    let subjectConfidence: Float?

    nonisolated init(subjectLabel: String?, subjectConfidence: Float? = nil) {
        self.subjectLabel = subjectLabel
        self.subjectConfidence = subjectConfidence
    }
}

enum FocusFailureKind: String, Codable, Equatable {
    case none
    case motionBlur
    case missedFocus

    var title: String {
        switch self {
        case .none: "None"
        case .motionBlur: "Motion blur"
        case .missedFocus: "Missed focus"
        }
    }
}

enum FocusMaskRegionSource: String, Codable, Equatable {
    case none
    case saliency
    case afPoint
    case saliencyAndAF

    var title: String {
        switch self {
        case .none: "None"
        case .saliency: "Saliency"
        case .afPoint: "AF point"
        case .saliencyAndAF: "AF + saliency"
        }
    }
}

enum FocusEvidenceRegion: String, Codable, Equatable {
    case none
    case afCenter
    case afNeighborhood
    case afPoint
    case saliency
    case global
    case mixed

    var title: String {
        switch self {
        case .none: "None"
        case .afCenter: "AF center"
        case .afNeighborhood: "AF neighborhood"
        case .afPoint: "AF point"
        case .saliency: "Saliency"
        case .global: "Global"
        case .mixed: "Mixed"
        }
    }

    nonisolated var isAFAnchored: Bool {
        switch self {
        case .afCenter, .afNeighborhood, .afPoint:
            true
        case .none, .saliency, .global, .mixed:
            false
        }
    }
}

struct FocusEvidence: Equatable {
    let winningRegion: FocusEvidenceRegion
    let globalScore: Float?
    let saliencyScore: Float?
    let afPointScore: Float?
    let afCenterScore: Float?
    let afNeighborhoodScore: Float?
    var effectiveVisualThreshold: Float?
    var maskCoverage: Float?
    var relaxedForVisibility: Bool

    nonisolated init(
        winningRegion: FocusEvidenceRegion,
        globalScore: Float?,
        saliencyScore: Float?,
        afPointScore: Float?,
        afCenterScore: Float? = nil,
        afNeighborhoodScore: Float? = nil,
        effectiveVisualThreshold: Float? = nil,
        maskCoverage: Float? = nil,
        relaxedForVisibility: Bool = false,
    ) {
        self.winningRegion = winningRegion
        self.globalScore = globalScore
        self.saliencyScore = saliencyScore
        self.afPointScore = afPointScore
        self.afCenterScore = afCenterScore
        self.afNeighborhoodScore = afNeighborhoodScore
        self.effectiveVisualThreshold = effectiveVisualThreshold
        self.maskCoverage = maskCoverage
        self.relaxedForVisibility = relaxedForVisibility
    }
}

struct SharpnessBreakdown: Equatable {
    let finalScore: Float
    let globalScore: Float?
    let subjectScore: Float?
    let afPointScore: Float?
    let blurGateSigma: Float
    let subjectLabel: String?
    let subjectConfidence: Float?
    let focusFailureKind: FocusFailureKind
    var focusMaskRegionSource: FocusMaskRegionSource?
    var focusMaskVisualThreshold: Float?
    var focusEvidence: FocusEvidence?
}

struct FocusDetectorConfig {
    /// Aperture-derived tuning hint. Wide-aperture shots have a narrow focus plane
    /// and deserve a stricter blur gate; landscape-aperture shots have deep DoF and
    /// should not be pre-blurred as aggressively nor weighted so heavily toward the
    /// Vision-detected salient region. `.mid` is the neutral baseline.
    /// Explicit nonisolated conformance — default-isolation=MainActor would otherwise
    /// make the synthesized Equatable.== main-isolated and unusable from the
    /// nonisolated scoring statics.
    enum ApertureHint: Equatable {
        case wide // ≤ f/5.6
        case mid // f/5.6–f/8
        case landscape // ≥ f/8

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case (.wide, .wide), (.mid, .mid), (.landscape, .landscape): true
            default: false
            }
        }
    }

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
    var guaranteeVisibleFocusEvidence: Bool = false
    var minimumEvidenceCoverage: Float = 0.001
    var afCenterRegionRadius: Float = 0.025
    var afNeighborhoodRegionRadius: Float = 0.075

    /// When true, the visual focus-mask overlay is clipped to the detected subject
    /// region, falling back to the camera AF point if Vision does not find a subject.
    /// This is overlay-only; scalar scoring still uses the subject/full-frame blend.
    var isolateMaskToSubject: Bool = true

    // MARK: Scoring-only parameters (do not affect the focus mask overlay)

    /// Fraction of image dimension excluded from each border when computing
    /// the full-frame sharpness score. Prevents Gaussian-blur edge artifacts
    /// from inflating the score. Range 0–0.10.
    var borderInsetFraction: Float = 0.04

    /// Weight given to the salient-region score vs the full-frame score.
    /// 0 = full-frame only, 1 = subject region only.
    var salientWeight: Float = 0.75

    /// Optional preset-level override for subject/full-frame blend weight.
    /// Takes precedence over aperture-derived overrides when set.
    var explicitSalientWeightOverride: Float?

    /// Bonus multiplier for subject size.
    var subjectSizeFactor: Float = 0.1

    /// Maximum reduction applied when a subject region is silhouette-dominated.
    /// 0 disables the penalty, 0.55 is the historical default.
    var silhouettePenaltyStrength: Float = 0.55

    /// Optional second fine-detail Laplacian pass blended into scoring. Higher values
    /// cost more compute but preserve small subject detail at larger scoring sizes.
    /// The focus mask overlay keeps using the primary pass.
    var fineDetailBlendWeight: Float = 0.0

    /// When true, runs VNClassifyImageRequest alongside saliency detection.
    var enableSubjectClassification: Bool = true

    /// Half-size of the AF-point scoring region as a fraction of image dimension.
    var afRegionRadius: Float = 0.12

    /// Aperture hint driving the soft blur-gate thresholds, the landscape blur damp,
    /// and the landscape salient-weight override. Set per-file by SharpnessScoringModel
    /// from EXIF; defaults to `.mid` when aperture is unknown.
    var apertureHint: ApertureHint = .mid
}

extension FocusDetectorConfig.ApertureHint {
    /// Lower end of the soft blur-gate ramp. Below this subject-region σ, the final
    /// score is multiplied by 0.20 (strong, but no longer the old 0.12 cliff).
    nonisolated var blurGateLow: Float {
        switch self {
        case .wide: 0.010
        case .mid: 0.008
        case .landscape: 0.006
        }
    }

    /// Upper end of the soft blur-gate ramp. Above this σ, no attenuation is applied.
    nonisolated var blurGateHigh: Float {
        switch self {
        case .wide: 0.025
        case .mid: 0.022
        case .landscape: 0.018
        }
    }

    /// Multiplier applied to the combined ISO × resolution blur factor. Landscape damps
    /// so deep-DoF scenes with real whole-frame detail aren't pre-blurred away.
    nonisolated var blurDamp: Float {
        switch self {
        case .wide, .mid: 1.0
        case .landscape: 0.8
        }
    }

    /// Overrides `config.salientWeight` when non-nil. Landscape reduces to 0.55 so that
    /// the Vision salient region does not dominate scoring on shots where the whole frame
    /// carries in-focus detail.
    nonisolated var salientWeightOverride: Float? {
        switch self {
        case .wide, .mid: nil
        case .landscape: 0.55
        }
    }

    /// Derives the hint from an EXIF f-number for aperture-aware scoring.
    nonisolated static func from(aperture: Double?) -> Self {
        guard let a = aperture else { return .mid }
        if a <= 5.6 { return .wide }
        if a >= 8.0 { return .landscape }
        return .mid
    }
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
            && lhs.guaranteeVisibleFocusEvidence == rhs.guaranteeVisibleFocusEvidence
            && lhs.minimumEvidenceCoverage == rhs.minimumEvidenceCoverage
            && lhs.afCenterRegionRadius == rhs.afCenterRegionRadius
            && lhs.afNeighborhoodRegionRadius == rhs.afNeighborhoodRegionRadius
            && lhs.isolateMaskToSubject == rhs.isolateMaskToSubject
            && lhs.borderInsetFraction == rhs.borderInsetFraction
            && lhs.salientWeight == rhs.salientWeight
            && lhs.explicitSalientWeightOverride == rhs.explicitSalientWeightOverride
            && lhs.subjectSizeFactor == rhs.subjectSizeFactor
            && lhs.silhouettePenaltyStrength == rhs.silhouettePenaltyStrength
            && lhs.fineDetailBlendWeight == rhs.fineDetailBlendWeight
            && lhs.enableSubjectClassification == rhs.enableSubjectClassification
            && lhs.afRegionRadius == rhs.afRegionRadius
            && lhs.apertureHint == rhs.apertureHint
    }
}

extension FocusDetectorConfig {
    /// Birds-in-flight preset.
    nonisolated static var birdsInFlight: FocusDetectorConfig {
        var c = FocusDetectorConfig()
        c.preBlurRadius = 2.2
        c.threshold = 0.46
        c.dilationRadius = 1.0
        c.erosionRadius = 1.0
        c.featherRadius = 2.0

        c.borderInsetFraction = 0.05
        c.salientWeight = 0.85
        c.subjectSizeFactor = 0.05
        c.silhouettePenaltyStrength = 0.55
        c.enableSubjectClassification = true
        c.isolateMaskToSubject = true
        c.afRegionRadius = 0.06
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

/// Immutable background engine for focus-mask rendering and sharpness scoring.
/// The engine is `@unchecked Sendable` because Core Image's `CIContext`
/// sendability is not fully expressed in Swift's type system. The invariant is
/// that the engine has no mutable model/UI state; callers pass immutable config
/// snapshots into every operation.
struct FocusMaskEngine: @unchecked Sendable {
    private nonisolated let context = CIContext(options: [
        .workingColorSpace: NSNull(),
        .workingFormat: CIFormat.RGBAf
    ])

    struct FocusMaskDiagnostics: Equatable {
        let regionSource: FocusMaskRegionSource
        let visualThreshold: Float?
    }

    struct FocusMaskRegionSelection: Equatable {
        nonisolated let saliencyRect: CGRect?
        nonisolated let afRect: CGRect?

        nonisolated var source: FocusMaskRegionSource {
            switch (saliencyRect, afRect) {
            case (.some, .some): .saliencyAndAF
            case (.some, nil): .saliency
            case (nil, .some): .afPoint
            case (nil, nil): .none
            }
        }
    }

    private struct FocusMaskRenderResult {
        let image: CGImage?
        let diagnostics: FocusMaskDiagnostics
        let evidence: FocusEvidence?
    }

    nonisolated init() {}

    // MARK: - Public API

    nonisolated func generateFocusMask(
        from cgImage: CGImage,
        scale: CGFloat,
        config: FocusDetectorConfig,
        afPoint: CGPoint? = nil,
    ) async -> CGImage? {
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let salientRegion: CGRect? = if config.isolateMaskToSubject {
                Self.detectSaliencyAndClassify(
                    for: cgImage,
                    classify: false,
                ).region
            } else {
                nil
            }

            return Self.buildFocusMask(
                from: CIImage(cgImage: cgImage),
                scale: scale,
                salientRegion: salientRegion,
                afPoint: afPoint,
                evidenceRegion: nil,
                evidence: nil,
                context: context,
                config: config,
            ).image
        }.value
    }

    nonisolated func generateFocusMaskWithBreakdown(
        from cgImage: CGImage,
        scale: CGFloat,
        config: FocusDetectorConfig,
        afPoint: CGPoint? = nil,
    ) async -> (mask: CGImage?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let context = self.context

        return await Task.detached(priority: .userInitiated) {
            let ciImage = CIImage(cgImage: cgImage)
            let (region, saliencyInfo) = Self.detectSaliencyAndClassify(
                for: cgImage,
                classify: config.enableSubjectClassification,
            )
            var breakdown = Self.computeSharpnessBreakdown(
                from: ciImage,
                salientRegion: region,
                saliencyInfo: saliencyInfo,
                afPoint: afPoint,
                context: context,
                config: config,
            )
            let maskResult = Self.buildFocusMask(
                from: ciImage,
                scale: scale,
                salientRegion: region,
                afPoint: afPoint,
                evidenceRegion: breakdown?.focusEvidence?.winningRegion,
                evidence: breakdown?.focusEvidence,
                context: context,
                config: config,
            )
            breakdown?.focusMaskRegionSource = maskResult.diagnostics.regionSource
            breakdown?.focusMaskVisualThreshold = maskResult.diagnostics.visualThreshold
            if let evidence = maskResult.evidence {
                breakdown?.focusEvidence = evidence
            }
            return (maskResult.image, saliencyInfo, breakdown)
        }.value
    }

    nonisolated func computeSharpnessScore(
        fromRawURL url: URL,
        config: FocusDetectorConfig,
        thumbnailMaxPixelSize: Int = 512,
        afPoint: CGPoint? = nil,
    ) async -> (score: Float?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        await Task.detached(priority: .userInitiated) { [context] in
            let binaryImg = Self.decodeBinaryFallback(at: url, maxPixelSize: thumbnailMaxPixelSize)

            let cgImage: CGImage
            if let img = binaryImg {
                cgImage = img
            } else {
                guard let img = Self.decodeThumbnail(at: url, maxPixelSize: thumbnailMaxPixelSize) else {
                    return (nil, nil, nil)
                }
                cgImage = img
            }

            let (region, saliencyInfo) = Self.detectSaliencyAndClassify(
                for: cgImage, classify: config.enableSubjectClassification,
            )
            let breakdown = Self.computeSharpnessBreakdown(
                from: CIImage(cgImage: cgImage),
                salientRegion: region,
                saliencyInfo: saliencyInfo,
                afPoint: afPoint,
                context: context,
                config: config,
            )
            return (breakdown?.finalScore, saliencyInfo, breakdown)
        }.value
    }

    // MARK: - Decode helpers

    private nonisolated static func decodeThumbnail(at url: URL, maxPixelSize: Int) -> CGImage? {
        let srcOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, srcOptions as CFDictionary) else { return nil }

        var thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        if maxPixelSize > 0 {
            thumbOptions[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary)
    }

    /// Binary fallback for ARW 6.0 (RA16) files from newer Sony bodies
    /// (A7V, A7R VI / ILCE-7RM6) where CGImageSourceCreateThumbnailAtIndex
    /// returns nil. Reads the embedded JPEG directly from the file bytes via
    /// SonyMakerNoteParser, bypassing the RA16 decoder entirely. Sony-only:
    /// other vendors (e.g. Nikon NEF) don't need this path and would hit a
    /// TIFF structure the Sony parser doesn't understand.
    private nonisolated static func decodeBinaryFallback(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard RawFormatRegistry.format(for: url) is SonyRawFormat.Type else { return nil }
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url),
              let loc = locations.preview ?? locations.thumbnail ?? locations.fullJPEG,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let raw: CGImage?
        if maxPixelSize > 0 {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            raw = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
        } else {
            raw = CGImageSourceCreateImageAtIndex(
                src,
                0,
                [kCGImageSourceShouldCacheImmediately: true] as CFDictionary,
            )
        }

        guard let raw else { return nil }

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
            space: srgb, bitmapInfo: bitmapInfo.rawValue,
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
        return (union, SaliencyInfo(subjectLabel: label, subjectConfidence: maxConfidence))
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

    /// Produces a single scalar sharpness score for an image.
    ///
    /// Pipeline:
    /// 1. `buildAmplifiedLaplacian` → Gaussian pre-blur + Metal Laplacian + gain.
    /// 2. Render to an RGBAf bitmap so each pixel's edge energy is a `Float` in `.r`.
    /// 3. Collect three sample sets:
    ///    * **full**: all pixels inside the border inset (Gaussian edge artefacts excluded).
    ///    * **salient**: pixels inside the Vision attention bounding box (if any).
    ///    * **AF**: pixels inside a square of half-size `afRegionRadius`
    ///      centered on the camera's AF point (if any).
    /// 4. Each set is reduced to a scalar via `robustTailScore` (p90–p97 band mean).
    /// 5. Blend:  `score = (1 − w)·full + w·subject`,  where
    ///    `subject = 0.6·AF + 0.4·saliency` (whichever are present) and
    ///    `w = config.explicitSalientWeightOverride ?? apertureHint override ?? config.salientWeight`.
    /// 6. Penalties/bonuses on top of the blend:
    ///    * silhouette penalty if >62 % of subject energy sits in its outer 12 % rim;
    ///    * subject-size bonus `(1 + area · subjectSizeFactor)` for saliency-only;
    ///    * soft aperture-aware blur gate `0.20…1.0` driven by subject micro-contrast σ.
    private struct SharpnessAnalysis {
        let finalScore: Float
        let fullScore: Float?
        let salientScore: Float?
        let afScore: Float?
        let afCenterScore: Float?
        let afNeighborhoodScore: Float?
        let subjectMicro: Float
        let evidenceRegion: FocusEvidenceRegion
    }

    private nonisolated static let motionBlurScoreThreshold: Float = 0.08
    private nonisolated static let motionBlurSigmaThreshold: Float = 0.012
    private nonisolated static let missedFocusMinimumGlobalScore: Float = 0.12
    private nonisolated static let missedFocusSubjectRatio: Float = 0.55

    private nonisolated static func computeSharpnessBreakdown(
        from inputImage: CIImage,
        salientRegion: CGRect?,
        saliencyInfo: SaliencyInfo?,
        afPoint: CGPoint?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> SharpnessBreakdown? {
        guard let analysis = computeSharpnessAnalysis(
            from: inputImage,
            salientRegion: salientRegion,
            afPoint: afPoint,
            context: context,
            config: config,
        ) else { return nil }

        return SharpnessBreakdown(
            finalScore: analysis.finalScore,
            globalScore: analysis.fullScore,
            subjectScore: analysis.salientScore,
            afPointScore: analysis.afScore,
            blurGateSigma: analysis.subjectMicro,
            subjectLabel: saliencyInfo?.subjectLabel,
            subjectConfidence: saliencyInfo?.subjectConfidence,
            focusFailureKind: classifyFocusFailure(
                globalScore: analysis.fullScore,
                subjectScore: analysis.salientScore,
                afPointScore: analysis.afScore,
                blurGateSigma: analysis.subjectMicro,
            ),
            focusEvidence: FocusEvidence(
                winningRegion: analysis.evidenceRegion,
                globalScore: analysis.fullScore,
                saliencyScore: analysis.salientScore,
                afPointScore: analysis.afScore,
                afCenterScore: analysis.afCenterScore,
                afNeighborhoodScore: analysis.afNeighborhoodScore,
            ),
        )
    }

    nonisolated static func classifyFocusFailure(
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
    ) -> FocusFailureKind {
        let subject = subjectScore ?? afPointScore
        let afOrSubject = afPointScore ?? subjectScore

        if (globalScore ?? 0) < motionBlurScoreThreshold,
           (subject ?? 0) < motionBlurScoreThreshold,
           (afOrSubject ?? 0) < motionBlurScoreThreshold,
           blurGateSigma < motionBlurSigmaThreshold {
            return .motionBlur
        }

        if let globalScore,
           let subject,
           globalScore >= missedFocusMinimumGlobalScore,
           subject / max(globalScore, 1e-6) < missedFocusSubjectRatio {
            return .missedFocus
        }

        return .none
    }

    nonisolated static func focusEvidenceRegion(
        globalScore: Float?,
        saliencyScore: Float?,
        afPointScore: Float?,
        afCenterScore: Float? = nil,
        afNeighborhoodScore: Float? = nil,
        afRegionRadius: Float,
    ) -> FocusEvidenceRegion {
        let validGlobal = globalScore.flatMap { $0.isFinite ? $0 : nil }
        let validSaliency = saliencyScore.flatMap { $0.isFinite ? $0 : nil }
        let validAF = afPointScore.flatMap { $0.isFinite ? $0 : nil }
        let validAFCenter = afCenterScore.flatMap { $0.isFinite ? $0 : nil }
        let validAFNeighborhood = afNeighborhoodScore.flatMap { $0.isFinite ? $0 : nil }

        guard validGlobal != nil || validSaliency != nil || validAF != nil || validAFCenter != nil || validAFNeighborhood != nil else {
            return .none
        }

        let strongestNonLocal = max(validGlobal ?? 0, validSaliency ?? 0, validAF ?? 0)
        if let center = validAFCenter, center >= strongestNonLocal * 0.82 {
            return .afCenter
        }

        if let neighborhood = validAFNeighborhood, neighborhood >= strongestNonLocal * 0.88 {
            return .afNeighborhood
        }

        if let af = validAF {
            let strongestOther = max(validGlobal ?? 0, validSaliency ?? 0)
            let wildlifeSizedAF = afRegionRadius > 0 && afRegionRadius <= 0.08
            if wildlifeSizedAF, af >= strongestOther * 0.85 {
                return .afPoint
            }

            if let saliency = validSaliency {
                let maxSubject = max(af, saliency)
                let minSubject = min(af, saliency)
                if maxSubject > 0, minSubject / maxSubject >= 0.92 {
                    return .mixed
                }
            }
        }

        let candidates: [(FocusEvidenceRegion, Float)] = [
            (.afCenter, validAFCenter ?? -.infinity),
            (.afNeighborhood, validAFNeighborhood ?? -.infinity),
            (.afPoint, validAF ?? -.infinity),
            (.saliency, validSaliency ?? -.infinity),
            (.global, validGlobal ?? -.infinity)
        ]
        return candidates.max(by: { $0.1 < $1.1 })?.0 ?? .none
    }

    private nonisolated static func computeSharpnessAnalysis(
        from inputImage: CIImage,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> SharpnessAnalysis? {
        guard let boosted = buildScoringLaplacian(from: inputImage, config: config) else { return nil }

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
            let borderFraction: Float // border energy / total; high => silhouette-dominated
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
        var afCenterScore: Float?
        var afNeighborhoodScore: Float?
        var afRegionUsed: CGRect?
        if let afRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afRegionRadius) {
            let a = analyzeRegion(afRegion)
            if a.samples.count >= 64 {
                afScore = Self.robustTailScore(a.samples)
                afRegionUsed = afRegion
                afAnalysis = a
            }
        }

        if let afCenterRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afCenterRegionRadius) {
            let a = analyzeRegion(afCenterRegion)
            if a.samples.count >= 16 {
                afCenterScore = Self.robustTailScore(a.samples)
            }
        }

        if let afNeighborhoodRegion = Self.afUnitRegion(afPoint: afPoint, radius: config.afNeighborhoodRegionRadius) {
            let a = analyzeRegion(afNeighborhoodRegion)
            if a.samples.count >= 64 {
                afNeighborhoodScore = Self.robustTailScore(a.samples)
            }
        }

        // AF and saliency both signal "where the subject is" but with different confidence
        // characteristics: AF is camera-provided ground truth for where focus was attempted;
        // Vision saliency is a perceptual model. Blending keeps both signals in the mix
        // rather than AF silently overriding saliency (the earlier `afScore ?? salientScore`
        // behaviour), which occasionally mis-ranked when the AF point landed on a secondary
        // subject while Vision correctly identified the main one.
        let effectiveSubjectScore: Float? = switch (afScore, salientScore) {
        case let (a?, s?): a * 0.6 + s * 0.4
        case let (a?, nil): a
        case let (nil, s?): s
        default: nil
        }
        // Prefer AF analysis for micro-contrast / silhouette because the AF region is
        // usually tighter than the Vision salient union.
        let effectiveAnalysis = afAnalysis ?? salientAnalysis

        // Soft blur gate: subject-region σ below blurGateLow → multiplier 0.20,
        // above blurGateHigh → 1.0, linearly ramped in between. Replaces an earlier
        // hard σ<0.014 → ×0.12 cliff that false-positived on low-contrast subjects
        // (white bird against white sky, fog, plain-backdrop portraits).
        let subjectMicro = effectiveAnalysis.map { Self.microContrast($0.samples) } ?? 0
        let hint = config.apertureHint
        let blurAttenuation: Float
        if let ea = effectiveAnalysis, ea.samples.count >= 64 {
            let lo = hint.blurGateLow
            let hi = hint.blurGateHigh
            let span = max(hi - lo, 1e-6)
            let t = min(max((subjectMicro - lo) / span, 0), 1)
            blurAttenuation = 0.20 + t * 0.80
        } else {
            blurAttenuation = 1.0
        }

        // Landscape (deep DoF) pulls the salient weight down so the full-frame score
        // is not dominated by the Vision salient region on scenes where the whole
        // frame carries real in-focus detail.
        let salientWeight = config.explicitSalientWeightOverride ?? hint.salientWeightOverride ?? config.salientWeight

        let base: Float?
        switch (fullScore, effectiveSubjectScore) {
        case let (f?, s?):
            var blended = f * (1.0 - salientWeight) + s * salientWeight

            // Silhouette penalty: if >62% of the subject-region edge energy sits in its
            // outer 12% border, we're measuring the silhouette rim rather than subject
            // detail (common on backlit wildlife). Reduce the score by up to 55%.
            if let ea = effectiveAnalysis, config.silhouettePenaltyStrength > 0 {
                let frac = ea.borderFraction
                let silhouetteT: Float = 0.62
                if frac > silhouetteT {
                    let over = min(1.0, (frac - silhouetteT) / (1.0 - silhouetteT))
                    blended *= 1.0 - config.silhouettePenaltyStrength * over
                }
            }

            // Subject-size bonus only for Vision saliency (not AF): when the AF point is
            // present we already have a high-confidence subject locus, so the
            // subject-area nudge would double-count.
            if afRegionUsed == nil, let region = salientRegion {
                let area = Float(region.width * region.height)
                blended *= 1.0 + area * config.subjectSizeFactor
            }

            base = blended

        case let (f?, nil):
            // Full-frame score but no subject locus: cube-of-(1-salientWeight) penalizes
            // heavily because for a wildlife-first app, "no detectable subject" usually
            // means the Vision saliency pass failed on a messy / low-contrast frame. The
            // landscape hint softens this via the reduced salientWeight override.
            let p = 1.0 - salientWeight
            base = f * p * p * p

        case let (nil, s?):
            base = s

        default:
            base = nil
        }

        guard let baseScore = base else { return nil }
        return SharpnessAnalysis(
            finalScore: baseScore * blurAttenuation,
            fullScore: fullScore,
            salientScore: salientScore,
            afScore: afScore,
            afCenterScore: afCenterScore,
            afNeighborhoodScore: afNeighborhoodScore,
            subjectMicro: subjectMicro,
            evidenceRegion: Self.focusEvidenceRegion(
                globalScore: fullScore,
                saliencyScore: salientScore,
                afPointScore: afScore,
                afCenterScore: afCenterScore,
                afNeighborhoodScore: afNeighborhoodScore,
                afRegionRadius: config.afRegionRadius,
            ),
        )
    }

    // MARK: - Mask generation

    /// ISO→blur multiplier. Piecewise-linear: flat below ISO 800 (A1 / A1 II base is
    /// clean at low ISO), gentle rise 1.0→1.6 through ISO 3200, then a shallow tail to a
    /// cap of 2.2 at ~ISO 9600+. Replaces an earlier `sqrt(iso/400)` clamped to 3.0, which
    /// over-blurred real fine detail at ISO 6400+ on Sony A1-series bodies where noise is
    /// still well-controlled. The robust p90–p97 tail mean in `robustTailScore` already
    /// tolerates sparse noise, so the previous aggressive cap wasn't needed.
    nonisolated static func isoScalingFactor(iso: Int) -> Float {
        let i = Float(max(iso, 100))
        switch i {
        case ..<800:
            return 1.0

        case 800 ..< 3200:
            return 1.0 + (i - 800) / 2400 * 0.6

        default:
            return min(1.6 + (i - 3200) / 6400 * 0.6, 2.2)
        }
    }

    /// Edge-energy pipeline shared by both the mask overlay and the scalar score:
    /// 1. Gaussian pre-blur, radius = `preBlurRadius · isoFactor · resFactor · blurDamp`.
    ///    * `isoFactor` ∈ [1.0, 2.2] — see `isoScalingFactor(iso:)`.
    ///    * `resFactor = clamp(sqrt(max(width, 512) / 512), 1, 3)` — longer sides get
    ///      proportionally more blur so edge detail is sampled at a comparable scale
    ///      regardless of thumbnail resolution.
    ///    * `blurDamp` is 0.8 for landscape apertures (deep DoF scenes), 1.0 otherwise.
    ///    * Capped at 100 px to avoid pathological radii from malformed input.
    /// 2. Metal `focusLaplacian` kernel → per-pixel 2nd-derivative energy.
    /// 3. `CIColorMatrix` scales R/G/B by `energyMultiplier` (tuned by calibration).
    private nonisolated static func buildAmplifiedLaplacian(from image: CIImage, config: FocusDetectorConfig) -> CIImage? {
        let isoFactor = Self.isoScalingFactor(iso: config.iso)
        let imageWidth = Float(image.extent.width)
        let resFactor = max(1.0, min(sqrt(max(imageWidth, 512.0) / 512.0), 3.0))
        // Landscape (deep DoF) damps the combined ISO × resolution blur so the whole-
        // frame edge energy isn't smoothed away before the Laplacian fires.
        let blurDamp = config.apertureHint.blurDamp
        let effectiveRadius = min(config.preBlurRadius * isoFactor * resFactor * blurDamp, 100.0)

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

    /// Scoring-only Laplacian. Slower quality modes blend the normal blur scale
    /// with a finer pass so small feathers, eyes, and eyelashes survive the
    /// noise-reduction pre-blur instead of being averaged away.
    private nonisolated static func buildScoringLaplacian(from image: CIImage, config: FocusDetectorConfig) -> CIImage? {
        guard let primary = buildAmplifiedLaplacian(from: image, config: config) else { return nil }
        let w = min(max(config.fineDetailBlendWeight, 0), 0.65)
        guard w > 0 else { return primary }

        var fineConfig = config
        fineConfig.preBlurRadius = max(0.35, config.preBlurRadius * 0.58)
        guard let fine = buildAmplifiedLaplacian(from: image, config: fineConfig) else { return primary }

        func scaled(_ input: CIImage, by amount: Float) -> CIImage? {
            let scale = CIFilter.colorMatrix()
            scale.inputImage = input
            scale.rVector = CIVector(x: CGFloat(amount), y: 0, z: 0, w: 0)
            scale.gVector = CIVector(x: 0, y: CGFloat(amount), z: 0, w: 0)
            scale.bVector = CIVector(x: 0, y: 0, z: CGFloat(amount), w: 0)
            scale.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return scale.outputImage
        }

        guard let primaryWeighted = scaled(primary, by: 1.0 - w),
              let fineWeighted = scaled(fine, by: w),
              let add = CIFilter(name: "CIAdditionCompositing")
        else { return primary }

        add.setValue(fineWeighted, forKey: kCIInputImageKey)
        add.setValue(primaryWeighted, forKey: kCIInputBackgroundImageKey)
        return add.outputImage?.cropped(to: primary.extent) ?? primary
    }

    private nonisolated static func buildFocusMask(
        from inputImage: CIImage,
        scale: CGFloat,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        evidenceRegion: FocusEvidenceRegion?,
        evidence: FocusEvidence?,
        context: CIContext,
        config: FocusDetectorConfig,
    ) -> FocusMaskRenderResult {
        let emptyDiagnostics = FocusMaskDiagnostics(regionSource: .none, visualThreshold: nil)
        let scaledImage = inputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let rawLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: config) else {
            return FocusMaskRenderResult(image: nil, diagnostics: emptyDiagnostics, evidence: evidence)
        }

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
            let selection = Self.focusMaskRegionSelection(
                extent: scaledImage.extent,
                salientRegion: config.isolateMaskToSubject ? salientRegion : nil,
                afPoint: config.isolateMaskToSubject ? afPoint : nil,
                afRegionRadius: config.afRegionRadius,
            )
            let cropped = boostedLaplacian.cropped(to: scaledImage.extent)
            return FocusMaskRenderResult(
                image: context.createCGImage(cropped, from: cropped.extent),
                diagnostics: FocusMaskDiagnostics(regionSource: selection.source, visualThreshold: nil),
                evidence: evidence,
            )
        }

        let selection = if config.isolateMaskToSubject {
            Self.focusMaskRegionSelection(
                extent: scaledImage.extent,
                salientRegion: salientRegion,
                afPoint: afPoint,
                afRegionRadius: config.afRegionRadius,
            )
        } else {
            FocusMaskRegionSelection(saliencyRect: scaledImage.extent, afRect: nil)
        }
        let afCenterRect = Self.pixelRect(
            from: Self.afUnitRegion(afPoint: afPoint, radius: config.afCenterRegionRadius),
            in: scaledImage.extent,
        )
        let afNeighborhoodRect = Self.pixelRect(
            from: Self.afUnitRegion(afPoint: afPoint, radius: config.afNeighborhoodRegionRadius),
            in: scaledImage.extent,
        )

        var masks = [CIImage]()
        var thresholds = [Float]()
        var coverages = [Float]()
        var maskClipRects = [CGRect]()
        var relaxedForVisibility = false

        func appendMask(
            rect: CGRect,
            sourceImage: CIImage,
            percentile: Float,
            floorMultiplier: Float,
            capAtFallback: Bool,
            erosionRadius: Float,
            dilationRadius: Float,
        ) {
            let samples = Self.redSamples(in: rect, from: sourceImage, context: context)
            var threshold = Self.adaptiveVisualThreshold(
                samples,
                fallback: config.threshold,
                percentile: percentile,
                floorMultiplier: floorMultiplier,
                capAtFallback: capAtFallback,
            )
            var coverage = Self.maskCoverage(samples, threshold: threshold)

            if config.guaranteeVisibleFocusEvidence, coverage < config.minimumEvidenceCoverage {
                let relaxed = Self.relaxedVisualThreshold(
                    samples,
                    currentThreshold: threshold,
                    minimumCoverage: config.minimumEvidenceCoverage,
                )
                threshold = relaxed.threshold
                coverage = relaxed.coverage
                relaxedForVisibility = relaxedForVisibility || relaxed.relaxed
            }

            if let mask = Self.thresholdedMask(
                from: sourceImage,
                in: rect,
                threshold: threshold,
                erosionRadius: erosionRadius,
                dilationRadius: dilationRadius,
                extent: scaledImage.extent,
            ) {
                masks.append(mask)
                maskClipRects.append(rect.integral.intersection(scaledImage.extent))
                thresholds.append(threshold)
                coverages.append(coverage)
            }
        }

        let requestedEvidenceRegion = evidenceRegion ?? .none
        let visualEvidenceRegion: FocusEvidenceRegion = switch requestedEvidenceRegion {
        case .afCenter where afCenterRect != nil:
            .afCenter

        case .afNeighborhood where afNeighborhoodRect != nil:
            .afNeighborhood

        case .afPoint where selection.afRect != nil:
            .afPoint

        case .saliency where selection.saliencyRect != nil:
            .saliency

        case .mixed where selection.afRect != nil || selection.saliencyRect != nil:
            .mixed

        case .global:
            .global

        default:
            switch (selection.afRect, selection.saliencyRect) {
            case (.some, _): .afPoint
            case (nil, .some): .saliency
            default: .global
            }
        }

        let fineLaplacian: CIImage?
        if selection.afRect != nil || afCenterRect != nil || afNeighborhoodRect != nil {
            var fineConfig = config
            fineConfig.preBlurRadius = max(0.35, config.preBlurRadius * 0.52)
            fineLaplacian = Self.buildAmplifiedLaplacian(from: scaledImage, config: fineConfig) ?? boostedLaplacian
        } else {
            fineLaplacian = nil
        }

        let afPixelCenter = Self.afPixelCenter(afPoint: afPoint, in: scaledImage.extent)
        func afWeightedSource(for rect: CGRect) -> CIImage {
            let source = fineLaplacian ?? boostedLaplacian
            guard let afPixelCenter,
                  let weighted = Self.centerWeightedLaplacian(
                    source,
                    center: afPixelCenter,
                    rect: rect,
                    extent: scaledImage.extent,
                  )
            else { return source }
            return weighted
        }

        switch visualEvidenceRegion {
        case .afCenter:
            if let afCenterRect {
                appendMask(
                    rect: afCenterRect,
                    sourceImage: afWeightedSource(for: afCenterRect),
                    percentile: 0.82,
                    floorMultiplier: 0.32,
                    capAtFallback: true,
                    erosionRadius: 0,
                    dilationRadius: min(config.dilationRadius, 0.75),
                )
            }

        case .afNeighborhood:
            if let afNeighborhoodRect {
                appendMask(
                    rect: afNeighborhoodRect,
                    sourceImage: afWeightedSource(for: afNeighborhoodRect),
                    percentile: 0.88,
                    floorMultiplier: 0.42,
                    capAtFallback: true,
                    erosionRadius: max(0, config.erosionRadius - 1.0),
                    dilationRadius: min(config.dilationRadius, 0.75),
                )
            }

        case .afPoint:
            if let afRect = selection.afRect {
                appendMask(
                    rect: afRect,
                    sourceImage: afWeightedSource(for: afRect),
                    percentile: 0.88,
                    floorMultiplier: 0.42,
                    capAtFallback: true,
                    erosionRadius: max(0, config.erosionRadius - 1.0),
                    dilationRadius: min(config.dilationRadius, 0.75),
                )
            }

        case .saliency:
            if let saliencyRect = selection.saliencyRect {
                appendMask(
                    rect: saliencyRect,
                    sourceImage: boostedLaplacian,
                    percentile: 0.95,
                    floorMultiplier: 1.0,
                    capAtFallback: false,
                    erosionRadius: config.erosionRadius,
                    dilationRadius: config.dilationRadius,
                )
            }

        case .mixed:
            if let afRect = selection.afRect {
                appendMask(
                    rect: afRect,
                    sourceImage: afWeightedSource(for: afRect),
                    percentile: 0.88,
                    floorMultiplier: 0.42,
                    capAtFallback: true,
                    erosionRadius: max(0, config.erosionRadius - 1.0),
                    dilationRadius: min(config.dilationRadius, 0.75),
                )
            }
            if let saliencyRect = selection.saliencyRect {
                appendMask(
                    rect: saliencyRect,
                    sourceImage: boostedLaplacian,
                    percentile: 0.95,
                    floorMultiplier: 1.0,
                    capAtFallback: false,
                    erosionRadius: config.erosionRadius,
                    dilationRadius: config.dilationRadius,
                )
            }

        case .global, .none:
            appendMask(
                rect: scaledImage.extent,
                sourceImage: boostedLaplacian,
                percentile: 0.97,
                floorMultiplier: 1.0,
                capAtFallback: false,
                erosionRadius: config.erosionRadius,
                dilationRadius: config.dilationRadius,
            )
        }

        let whiteMask: CIImage = switch masks.count {
        case 0:
            CIImage(color: .black).cropped(to: scaledImage.extent)

        case 1:
            masks[0]

        default:
            masks.dropFirst().reduce(masks[0]) { partial, next in
                Self.maximumComposite(next, over: partial).cropped(to: scaledImage.extent)
            }
        }

        let redMatrix = CIFilter.colorMatrix()
        redMatrix.inputImage = whiteMask
        redMatrix.rVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        redMatrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        redMatrix.aVector = CIVector(x: 1, y: 0, z: 0, w: 0)
        guard let redMask = redMatrix.outputImage else {
            return FocusMaskRenderResult(
                image: nil,
                diagnostics: FocusMaskDiagnostics(regionSource: selection.source, visualThreshold: thresholds.min()),
                evidence: Self.focusEvidenceDiagnostics(
                    from: evidence,
                    visualRegion: visualEvidenceRegion,
                    threshold: thresholds.min(),
                    coverage: coverages.max(),
                    relaxedForVisibility: relaxedForVisibility,
                ),
            )
        }

        let feathered: CIImage
        if config.featherRadius > 0 {
            let featherBlur = CIFilter.gaussianBlur()
            featherBlur.inputImage = redMask
            featherBlur.radius = config.featherRadius
            feathered = featherBlur.outputImage ?? redMask
        } else {
            feathered = redMask
        }

        let croppedMask: CIImage
        if visualEvidenceRegion.isAFAnchored,
           let clip = Self.union(maskClipRects),
           !clip.isNull,
           !clip.isEmpty {
            let pad = CGFloat(max(config.featherRadius, 0))
            let paddedClip = clip.insetBy(dx: -pad, dy: -pad).intersection(scaledImage.extent)
            let blackBg = CIImage(color: .black).cropped(to: scaledImage.extent)
            croppedMask = feathered
                .cropped(to: paddedClip)
                .composited(over: blackBg)
                .cropped(to: scaledImage.extent)
        } else {
            croppedMask = feathered.cropped(to: scaledImage.extent)
        }
        return FocusMaskRenderResult(
            image: context.createCGImage(croppedMask, from: croppedMask.extent),
            diagnostics: FocusMaskDiagnostics(regionSource: selection.source, visualThreshold: thresholds.min()),
            evidence: Self.focusEvidenceDiagnostics(
                from: evidence,
                visualRegion: visualEvidenceRegion,
                threshold: thresholds.min(),
                coverage: coverages.max(),
                relaxedForVisibility: relaxedForVisibility,
            ),
        )
    }

    nonisolated static func focusMaskRegionSelection(
        extent: CGRect,
        salientRegion: CGRect?,
        afPoint: CGPoint?,
        afRegionRadius: Float,
    ) -> FocusMaskRegionSelection {
        let unitBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let saliencyUnitRect: CGRect? = if let salientRegion, !salientRegion.isNull, !salientRegion.isEmpty {
            salientRegion.intersection(unitBounds)
        } else {
            nil
        }

        let afUnitRect: CGRect? = {
            guard let afPoint, afRegionRadius > 0 else { return nil }
            let r = CGFloat(afRegionRadius)
            let visionY = 1.0 - afPoint.y
            let afRegion = CGRect(
                x: afPoint.x - r,
                y: visionY - r,
                width: r * 2,
                height: r * 2,
            )
            let intersection = afRegion.intersection(unitBounds)
            return intersection.isNull || intersection.isEmpty ? nil : intersection
        }()

        func pixelRect(from unitRegion: CGRect?) -> CGRect? {
            guard let unitRegion, !unitRegion.isNull, !unitRegion.isEmpty else { return nil }
            let rect = CGRect(
                x: extent.minX + unitRegion.minX * extent.width,
                y: extent.minY + (1.0 - unitRegion.maxY) * extent.height,
                width: unitRegion.width * extent.width,
                height: unitRegion.height * extent.height,
            ).integral.intersection(extent)
            return rect.isNull || rect.isEmpty ? nil : rect
        }

        return FocusMaskRegionSelection(
            saliencyRect: pixelRect(from: saliencyUnitRect),
            afRect: pixelRect(from: afUnitRect),
        )
    }

    nonisolated static func afUnitRegion(afPoint: CGPoint?, radius: Float) -> CGRect? {
        guard let afPoint, radius > 0 else { return nil }
        let unitBounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        let r = CGFloat(radius)
        let visionY = 1.0 - afPoint.y
        let region = CGRect(
            x: afPoint.x - r,
            y: visionY - r,
            width: r * 2,
            height: r * 2,
        ).intersection(unitBounds)
        return region.isNull || region.isEmpty ? nil : region
    }

    nonisolated static func pixelRect(from unitRegion: CGRect?, in extent: CGRect) -> CGRect? {
        guard let unitRegion, !unitRegion.isNull, !unitRegion.isEmpty else { return nil }
        let rect = CGRect(
            x: extent.minX + unitRegion.minX * extent.width,
            y: extent.minY + (1.0 - unitRegion.maxY) * extent.height,
            width: unitRegion.width * extent.width,
            height: unitRegion.height * extent.height,
        ).integral.intersection(extent)
        return rect.isNull || rect.isEmpty ? nil : rect
    }

    nonisolated static func afPixelCenter(afPoint: CGPoint?, in extent: CGRect) -> CGPoint? {
        guard let afPoint else { return nil }
        return CGPoint(
            x: extent.minX + afPoint.x * extent.width,
            y: extent.minY + afPoint.y * extent.height,
        )
    }

    private nonisolated static func union(_ rects: [CGRect]) -> CGRect? {
        let validRects = rects.filter { !$0.isNull && !$0.isEmpty }
        guard let first = validRects.first else { return nil }
        return validRects.dropFirst().reduce(first) { partial, rect in
            partial.union(rect)
        }
    }

    nonisolated static func adaptiveVisualThreshold(
        _ samples: [Float],
        fallback: Float,
        percentile: Float,
        floorMultiplier: Float,
        capAtFallback: Bool,
    ) -> Float {
        let floor = max(fallback * floorMultiplier, 0.01)
        let finite = samples.filter { $0.isFinite && $0 > 0 }
        guard !finite.isEmpty else {
            return min(floor, 0.95)
        }

        var sorted = finite
        vDSP.sort(&sorted, sortOrder: .ascending)
        let p = min(max(percentile, 0), 1)
        let index = min(max(Int(Float(sorted.count - 1) * p), 0), sorted.count - 1)
        let adaptive = capAtFallback ? min(sorted[index], fallback) : sorted[index]
        return min(max(adaptive, floor), 0.95)
    }

    nonisolated static func maskCoverage(_ samples: [Float], threshold: Float) -> Float {
        let finite = samples.filter(\.isFinite)
        guard !finite.isEmpty, threshold.isFinite else { return 0 }
        let covered = finite.reduce(0) { partial, value in
            partial + (value >= threshold ? 1 : 0)
        }
        return Float(covered) / Float(finite.count)
    }

    nonisolated static func relaxedVisualThreshold(
        _ samples: [Float],
        currentThreshold: Float,
        minimumCoverage: Float,
    ) -> (threshold: Float, coverage: Float, relaxed: Bool) {
        let finite = samples.filter { $0.isFinite && $0 > 0 }
        let currentCoverage = maskCoverage(samples, threshold: currentThreshold)
        let targetCoverage = min(max(minimumCoverage, 0), 1)
        guard targetCoverage > 0, currentCoverage < targetCoverage, !finite.isEmpty else {
            return (currentThreshold, currentCoverage, false)
        }

        var sorted = finite
        vDSP.sort(&sorted, sortOrder: .ascending)
        let coveredCount = max(1, Int(ceil(Float(sorted.count) * targetCoverage)))
        let index = min(max(sorted.count - coveredCount, 0), sorted.count - 1)
        let relaxedThreshold = min(currentThreshold, sorted[index])
        let relaxedCoverage = maskCoverage(samples, threshold: relaxedThreshold)
        return (relaxedThreshold, relaxedCoverage, relaxedThreshold < currentThreshold)
    }

    private nonisolated static func focusEvidenceDiagnostics(
        from evidence: FocusEvidence?,
        visualRegion: FocusEvidenceRegion,
        threshold: Float?,
        coverage: Float?,
        relaxedForVisibility: Bool,
    ) -> FocusEvidence {
        if var evidence {
            evidence.effectiveVisualThreshold = threshold
            evidence.maskCoverage = coverage
            evidence.relaxedForVisibility = relaxedForVisibility
            return evidence
        }

        return FocusEvidence(
            winningRegion: visualRegion,
            globalScore: nil,
            saliencyScore: nil,
            afPointScore: nil,
            effectiveVisualThreshold: threshold,
            maskCoverage: coverage,
            relaxedForVisibility: relaxedForVisibility,
        )
    }

    private nonisolated static func redSamples(in rect: CGRect, from image: CIImage, context: CIContext) -> [Float] {
        let bounds = rect.integral.intersection(image.extent)
        guard !bounds.isNull, !bounds.isEmpty else { return [] }

        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard width > 0, height > 0 else { return [] }

        var rgba = [Float](repeating: 0, count: width * height * 4)
        context.render(
            image,
            toBitmap: &rgba,
            rowBytes: width * 16,
            bounds: bounds,
            format: .RGBAf,
            colorSpace: nil,
        )
        return stride(from: 0, to: rgba.count, by: 4).compactMap { idx in
            let value = rgba[idx]
            return value.isFinite ? value : nil
        }
    }

    private nonisolated static func thresholdedMask(
        from image: CIImage,
        in rect: CGRect,
        threshold: Float,
        erosionRadius: Float,
        dilationRadius: Float,
        extent: CGRect,
    ) -> CIImage? {
        let blackBg = CIImage(color: .black).cropped(to: extent)
        let regionImage = image
            .cropped(to: rect.integral.intersection(extent))
            .composited(over: blackBg)

        let thresholdFilter = CIFilter.colorThreshold()
        thresholdFilter.inputImage = regionImage
        thresholdFilter.threshold = threshold
        guard let thresholdedEdges = thresholdFilter.outputImage else { return nil }

        let erosionPx = Self.morphologyPixelRadius(erosionRadius)
        let eroded: CIImage
        if erosionPx > 0, let erode = CIFilter(name: "CIMorphologyMinimum") {
            erode.setValue(thresholdedEdges, forKey: kCIInputImageKey)
            erode.setValue(erosionPx, forKey: kCIInputRadiusKey)
            eroded = erode.outputImage ?? thresholdedEdges
        } else {
            eroded = thresholdedEdges
        }

        let dilationPx = Self.morphologyPixelRadius(dilationRadius)
        if dilationPx > 0, let dilate = CIFilter(name: "CIMorphologyMaximum") {
            dilate.setValue(eroded, forKey: kCIInputImageKey)
            dilate.setValue(dilationPx, forKey: kCIInputRadiusKey)
            return (dilate.outputImage ?? eroded).cropped(to: extent)
        }

        return eroded.cropped(to: extent)
    }

    private nonisolated static func centerWeightedLaplacian(
        _ image: CIImage,
        center: CGPoint,
        rect: CGRect,
        extent: CGRect,
    ) -> CIImage? {
        let outerRadius = max(min(rect.width, rect.height) * 0.52, 1)
        let innerRadius = max(outerRadius * 0.18, 1)
        let radial = CIFilter.radialGradient()
        radial.center = center
        radial.radius0 = Float(innerRadius)
        radial.radius1 = Float(outerRadius)
        radial.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 1)
        radial.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 1)
        guard let mask = radial.outputImage?.cropped(to: extent),
              let multiply = CIFilter(name: "CIMultiplyCompositing")
        else { return nil }
        multiply.setValue(mask, forKey: kCIInputImageKey)
        multiply.setValue(image, forKey: kCIInputBackgroundImageKey)
        return multiply.outputImage?.cropped(to: extent)
    }

    private nonisolated static func maximumComposite(_ image: CIImage, over background: CIImage) -> CIImage {
        if let maxFilter = CIFilter(name: "CIMaximumCompositing") {
            maxFilter.setValue(image, forKey: kCIInputImageKey)
            maxFilter.setValue(background, forKey: kCIInputBackgroundImageKey)
            return maxFilter.outputImage ?? image.composited(over: background)
        }
        return image.composited(over: background)
    }

    @inline(__always)
    private nonisolated static func morphologyPixelRadius(_ r: Float) -> Int {
        max(0, Int(r.rounded()))
    }
}

struct FocusCalibrationResult {
    let threshold: Float
    let energyMultiplier: Float
    let sampleCount: Int
    let p50: Float
    let p90: Float
    let p95: Float
    let p99: Float
}

@Observable @MainActor
final class FocusMaskModel {
    var config = FocusDetectorConfig()

    private nonisolated let engine = FocusMaskEngine()

    func generateFocusMask(
        from nsImage: NSImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
    ) async -> NSImage? {
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let originalSize = nsImage.size
        let config = configOverride ?? self.config

        guard let result = await engine.generateFocusMask(
            from: cgImage,
            scale: scale,
            config: config,
            afPoint: afPoint,
        ) else { return nil }

        return NSImage(cgImage: result, size: originalSize)
    }

    func generateFocusMaskWithBreakdown(
        from cgImage: CGImage,
        scale: CGFloat,
        configOverride: FocusDetectorConfig? = nil,
        afPoint: CGPoint? = nil,
    ) async -> (mask: CGImage?, saliency: SaliencyInfo?, breakdown: SharpnessBreakdown?) {
        let config = configOverride ?? self.config
        return await engine.generateFocusMaskWithBreakdown(
            from: cgImage,
            scale: scale,
            config: config,
            afPoint: afPoint,
        )
    }

    nonisolated static func robustTailScore(_ samples: [Float]) -> Float? {
        FocusMaskEngine.robustTailScore(samples)
    }

    nonisolated static func microContrast(_ samples: [Float]) -> Float {
        FocusMaskEngine.microContrast(samples)
    }

    nonisolated static func isoScalingFactor(iso: Int) -> Float {
        FocusMaskEngine.isoScalingFactor(iso: iso)
    }

    nonisolated static func classifyFocusFailure(
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
    ) -> FocusFailureKind {
        FocusMaskEngine.classifyFocusFailure(
            globalScore: globalScore,
            subjectScore: subjectScore,
            afPointScore: afPointScore,
            blurGateSigma: blurGateSigma,
        )
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
        baseConfigOverride: FocusDetectorConfig? = nil,
        thumbnailMaxPixelSize: Int = 512,
        thresholdPercentile: Float = 0.90,
        targetP95AfterGain: Float = 0.50,
        minSamples: Int = 5,
        maxConcurrentTasks: Int = 8,
    ) async -> FocusCalibrationResult? {
        let base = baseConfigOverride ?? config
        guard let result = await engine.calibrateFromBurstParallel(
            files: files,
            baseConfig: base,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            thresholdPercentile: thresholdPercentile,
            targetP95AfterGain: targetP95AfterGain,
            minSamples: minSamples,
            maxConcurrentTasks: maxConcurrentTasks,
        ) else { return nil }

        applyCalibration(result)
        return result
    }
}

extension FocusMaskEngine {
    /// Burst-based auto-calibration of `threshold` and `energyMultiplier`.
    ///
    /// Scores every file with `energyMultiplier = 1.0` (unit gain), collects the
    /// resulting raw scores, sorts them, then derives:
    ///
    ///     gain      = clamp(targetP95AfterGain / p95, 0.5, 32.0)
    ///     threshold = min(percentile(scores, thresholdPercentile) · gain, 1.0)
    ///
    /// The idea: after applying `gain`, the 95-th percentile of the catalog lands
    /// at `targetP95AfterGain` (default 0.50), giving consistent mask contrast
    /// across bright/dim or noisy/clean burst sets.  The threshold is placed at
    /// the chosen percentile (default 90-th) of the *post-gain* distribution so
    /// roughly the top 10 % of edges survive the threshold into the focus mask.
    ///
    /// Returns `nil` when fewer than `minSamples` files produced a usable score.
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
                    let result = await computeSharpnessScore(
                        fromRawURL: entry.url,
                        config: fileConfig,
                        thumbnailMaxPixelSize: tSize,
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
                        let result = await computeSharpnessScore(
                            fromRawURL: entry.url,
                            config: fileConfig,
                            thumbnailMaxPixelSize: tSize,
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
            p99: p99,
        )
    }
}
