import AppKit
import Foundation
import RawCullCore

struct SaliencyCandidate: Equatable {
    nonisolated let normalizedRect: CGRect
    nonisolated let confidence: Float
}

struct SaliencyDetection {
    nonisolated let candidates: [SaliencyCandidate]
    nonisolated let saliencyInfo: SaliencyInfo?
}

struct SaliencySelection: Equatable {
    nonisolated let candidateCount: Int
    nonisolated let winningRegion: CGRect?
    nonisolated let reason: String?
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

enum FocusEvidenceOverlayStyle: String, Codable, Equatable {
    case subjectEdges
    case globalEdges

    var title: String {
        switch self {
        case .subjectEdges: "Subject edges"
        case .globalEdges: "Muted global edges"
        }
    }
}

enum FocusEvidenceConfidence: String, Codable, Equatable {
    case high
    case medium
    case low

    var title: String {
        rawValue.capitalized
    }
}

struct FocusPatchRanking: Equatable {
    nonisolated let normalizedRect: CGRect
    nonisolated let robustTailScore: Float
    nonisolated let microContrast: Float
    nonisolated let coverage: Float
    nonisolated let distanceToAF: Float?
    nonisolated let silhouetteFraction: Float
    nonisolated let ringDetailScore: Float
    nonisolated let compactDetailScore: Float
    nonisolated let linearEdgePenalty: Float
    nonisolated let belowAFPenalty: Float
    nonisolated let eyeHeadHeuristicAdjustment: Float
    nonisolated let compositeScore: Float
    nonisolated let containsAFPoint: Bool

    nonisolated init(
        normalizedRect: CGRect,
        robustTailScore: Float,
        microContrast: Float,
        coverage: Float,
        distanceToAF: Float?,
        silhouetteFraction: Float,
        ringDetailScore: Float = 0,
        compactDetailScore: Float = 0,
        linearEdgePenalty: Float = 0,
        belowAFPenalty: Float = 0,
        eyeHeadHeuristicAdjustment: Float = 0,
        compositeScore: Float,
        containsAFPoint: Bool,
    ) {
        self.normalizedRect = normalizedRect
        self.robustTailScore = robustTailScore
        self.microContrast = microContrast
        self.coverage = coverage
        self.distanceToAF = distanceToAF
        self.silhouetteFraction = silhouetteFraction
        self.ringDetailScore = ringDetailScore
        self.compactDetailScore = compactDetailScore
        self.linearEdgePenalty = linearEdgePenalty
        self.belowAFPenalty = belowAFPenalty
        self.eyeHeadHeuristicAdjustment = eyeHeadHeuristicAdjustment
        self.compositeScore = compositeScore
        self.containsAFPoint = containsAFPoint
    }

    nonisolated static func == (lhs: FocusPatchRanking, rhs: FocusPatchRanking) -> Bool {
        lhs.normalizedRect == rhs.normalizedRect
            && lhs.robustTailScore == rhs.robustTailScore
            && lhs.microContrast == rhs.microContrast
            && lhs.coverage == rhs.coverage
            && lhs.distanceToAF == rhs.distanceToAF
            && lhs.silhouetteFraction == rhs.silhouetteFraction
            && lhs.ringDetailScore == rhs.ringDetailScore
            && lhs.compactDetailScore == rhs.compactDetailScore
            && lhs.linearEdgePenalty == rhs.linearEdgePenalty
            && lhs.belowAFPenalty == rhs.belowAFPenalty
            && lhs.eyeHeadHeuristicAdjustment == rhs.eyeHeadHeuristicAdjustment
            && lhs.compositeScore == rhs.compositeScore
            && lhs.containsAFPoint == rhs.containsAFPoint
    }
}

struct FocusEvidence: Equatable {
    nonisolated let winningRegion: FocusEvidenceRegion
    nonisolated let afCenterScore: Float?
    nonisolated let afNeighborhoodScore: Float?
    nonisolated var effectiveVisualThreshold: Float?
    nonisolated var maskCoverage: Float?
    nonisolated var relaxedForVisibility: Bool
    nonisolated var visualizedRegion: FocusEvidenceRegion?
    nonisolated var afDistanceFromCentroid: Float?
    nonisolated var patchRankings: [FocusPatchRanking]
    nonisolated var overlayStyle: FocusEvidenceOverlayStyle?
    nonisolated var focusEvidenceConfidence: FocusEvidenceConfidence?
    nonisolated var focusEvidenceConfidenceReason: String?
    nonisolated var spatialAlignmentScore: Float?
    nonisolated var localPatchDominance: Float?
    nonisolated var silhouettePenaltyApplied: Bool
    nonisolated var scoringAFLocalPatchScore: Float?
    nonisolated var scoringSubjectInteriorPatchScore: Float?
    nonisolated var scoringLocalDetailScore: Float?
    nonisolated var saliencyCandidateCount: Int
    nonisolated var winningSaliencyRect: CGRect?
    nonisolated var saliencySelectionReason: String?

    nonisolated init(
        winningRegion: FocusEvidenceRegion,
        afCenterScore: Float? = nil,
        afNeighborhoodScore: Float? = nil,
        effectiveVisualThreshold: Float? = nil,
        maskCoverage: Float? = nil,
        relaxedForVisibility: Bool = false,
        visualizedRegion: FocusEvidenceRegion? = nil,
        afDistanceFromCentroid: Float? = nil,
        patchRankings: [FocusPatchRanking] = [],
        overlayStyle: FocusEvidenceOverlayStyle? = nil,
        focusEvidenceConfidence: FocusEvidenceConfidence? = nil,
        focusEvidenceConfidenceReason: String? = nil,
        spatialAlignmentScore: Float? = nil,
        localPatchDominance: Float? = nil,
        silhouettePenaltyApplied: Bool = false,
        scoringAFLocalPatchScore: Float? = nil,
        scoringSubjectInteriorPatchScore: Float? = nil,
        scoringLocalDetailScore: Float? = nil,
        saliencyCandidateCount: Int = 0,
        winningSaliencyRect: CGRect? = nil,
        saliencySelectionReason: String? = nil,
    ) {
        self.winningRegion = winningRegion
        self.afCenterScore = afCenterScore
        self.afNeighborhoodScore = afNeighborhoodScore
        self.effectiveVisualThreshold = effectiveVisualThreshold
        self.maskCoverage = maskCoverage
        self.relaxedForVisibility = relaxedForVisibility
        self.visualizedRegion = visualizedRegion
        self.afDistanceFromCentroid = afDistanceFromCentroid
        self.patchRankings = patchRankings
        self.overlayStyle = overlayStyle
        self.focusEvidenceConfidence = focusEvidenceConfidence
        self.focusEvidenceConfidenceReason = focusEvidenceConfidenceReason
        self.spatialAlignmentScore = spatialAlignmentScore
        self.localPatchDominance = localPatchDominance
        self.silhouettePenaltyApplied = silhouettePenaltyApplied
        self.scoringAFLocalPatchScore = scoringAFLocalPatchScore
        self.scoringSubjectInteriorPatchScore = scoringSubjectInteriorPatchScore
        self.scoringLocalDetailScore = scoringLocalDetailScore
        self.saliencyCandidateCount = saliencyCandidateCount
        self.winningSaliencyRect = winningSaliencyRect
        self.saliencySelectionReason = saliencySelectionReason
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
    var scoringSource: SharpnessScoringSource = .embeddedPreview
}
