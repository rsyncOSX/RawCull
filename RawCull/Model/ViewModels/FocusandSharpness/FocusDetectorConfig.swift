import Foundation

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
