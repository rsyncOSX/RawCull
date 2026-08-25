import Foundation
import PhotoAnalysisKit

typealias FocusDetectorConfig = PhotoAnalysisKit.SharpnessConfiguration
typealias FocusFailureKind = PhotoAnalysisKit.FocusFailureKind
typealias FocusMaskRegionSource = PhotoAnalysisKit.FocusMaskRegionSource
typealias FocusPatchRanking = PhotoAnalysisKit.FocusPatchRanking
typealias FocusEvidence = PhotoAnalysisKit.FocusEvidence
typealias FocusCalibrationResult = PhotoAnalysisKit.FocusCalibrationResult

/// RawCull presentation metadata layered over PhotoAnalysisKit's neutral result.
nonisolated struct SharpnessBreakdown: Equatable, Sendable {
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
    var scoringSource: SharpnessScoringSource = .embeddedPreview

    init(
        finalScore: Float,
        globalScore: Float?,
        subjectScore: Float?,
        afPointScore: Float?,
        blurGateSigma: Float,
        subjectLabel: String?,
        subjectConfidence: Float?,
        focusFailureKind: FocusFailureKind,
        focusMaskRegionSource: FocusMaskRegionSource? = nil,
        focusMaskVisualThreshold: Float? = nil,
        focusEvidence: FocusEvidence? = nil,
        scoringSource: SharpnessScoringSource = .embeddedPreview,
    ) {
        self.finalScore = finalScore
        self.globalScore = globalScore
        self.subjectScore = subjectScore
        self.afPointScore = afPointScore
        self.blurGateSigma = blurGateSigma
        self.subjectLabel = subjectLabel
        self.subjectConfidence = subjectConfidence
        self.focusFailureKind = focusFailureKind
        self.focusMaskRegionSource = focusMaskRegionSource
        self.focusMaskVisualThreshold = focusMaskVisualThreshold
        self.focusEvidence = focusEvidence
        self.scoringSource = scoringSource
    }

    init(
        package breakdown: PhotoAnalysisKit.SharpnessBreakdown,
        scoringSource: SharpnessScoringSource,
    ) {
        self.init(
            finalScore: breakdown.finalScore,
            globalScore: breakdown.globalScore,
            subjectScore: breakdown.subjectScore,
            afPointScore: breakdown.afPointScore,
            blurGateSigma: breakdown.blurGateSigma,
            subjectLabel: breakdown.subjectLabel,
            subjectConfidence: breakdown.subjectConfidence,
            focusFailureKind: breakdown.focusFailureKind,
            focusMaskRegionSource: breakdown.focusMaskRegionSource,
            focusMaskVisualThreshold: breakdown.focusMaskVisualThreshold,
            focusEvidence: breakdown.focusEvidence,
            scoringSource: scoringSource,
        )
    }
}

extension PhotoAnalysisKit.FocusFailureKind {
    nonisolated var title: String {
        switch self {
        case .none: "None"
        case .motionBlur: "Motion blur"
        case .missedFocus: "Missed focus"
        }
    }
}

extension PhotoAnalysisKit.FocusMaskRegionSource {
    nonisolated var title: String {
        switch self {
        case .none: "None"
        case .saliency: "Saliency"
        case .afPoint: "AF point"
        case .saliencyAndAF: "AF + saliency"
        }
    }
}

extension PhotoAnalysisKit.FocusEvidenceRegion {
    nonisolated var title: String {
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
}

extension PhotoAnalysisKit.FocusEvidenceOverlayStyle {
    nonisolated var title: String {
        switch self {
        case .subjectEdges: "Subject edges"
        case .globalEdges: "Muted global edges"
        }
    }
}

extension PhotoAnalysisKit.FocusEvidenceConfidence {
    nonisolated var title: String {
        rawValue.capitalized
    }
}
