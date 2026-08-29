import CoreGraphics
import Foundation
import RawCullCore

struct ZoomCullingMetadata: Equatable {
    struct Sharpness: Equatable {
        let score: Float?
        let maxScore: Float
        let breakdown: SharpnessBreakdown?
    }

    struct BurstDecision: Equatable {
        let rank: Int
        let count: Int
        let score: Float?
        let isRecommendation: Bool
    }

    struct CLIPSemanticMatch: Equatable {
        let rank: Int
        let score: Float
    }

    enum CLIPSimilarity: Equatable {
        case anchor
        case distance(Float)
    }

    let sharpness: Sharpness?
    let normalizedAFPoint: CGPoint?
    let burstDecision: BurstDecision?
    let clipSemanticMatch: CLIPSemanticMatch?
    let clipSimilarity: CLIPSimilarity?

    @MainActor
    static func make(
        for file: FileItem,
        viewModel: RawCullViewModel,
        semanticSearchFeature: RawCullSemanticSearchFeature,
        burstAnalysis: BurstAnalysisResult? = nil,
    ) -> Self {
        let sharpnessModel = viewModel.sharpnessModel
        let sharpnessScore = sharpnessModel.scores[file.id]
        let breakdown = sharpnessModel.breakdowns[file.id]
        let candidateIndex = burstAnalysis?.candidates.firstIndex { $0.fileID == file.id }
        let candidate = candidateIndex.flatMap { burstAnalysis?.candidates[$0] }

        return Self(
            sharpness: sharpnessScore == nil && breakdown == nil ? nil : Sharpness(
                score: sharpnessScore,
                maxScore: sharpnessModel.maxScore,
                breakdown: breakdown,
            ),
            normalizedAFPoint: file.afFocusNormalized,
            burstDecision: candidateIndex.map {
                BurstDecision(
                    rank: $0 + 1,
                    count: burstAnalysis?.candidates.count ?? 0,
                    score: candidate?.overallScore,
                    isRecommendation: burstAnalysis?.recommendedFileID == file.id,
                )
            },
            clipSemanticMatch: semanticSearchFeature
                .resultEvidence(for: file.id)
                .map {
                    CLIPSemanticMatch(rank: $0.rank, score: $0.score)
                },
            clipSimilarity: clipSimilarity(
                for: file,
                similarityFeature: viewModel.similarityFeature,
            ),
        )
    }

    @MainActor
    private static func clipSimilarity(
        for file: FileItem,
        similarityFeature: RawCullSimilarityFeature,
    ) -> CLIPSimilarity? {
        switch similarityFeature.evidence(for: file.id) {
        case .anchor:
            return .anchor
        case let .distance(distance):
            return .distance(distance)
        case nil:
            return nil
        }
    }
}

extension ZoomCullingMetadata {
    var hasDecisionEvidence: Bool {
        !decisionRows.isEmpty
    }

    var decisionRows: [MetadataRow] {
        [
            sharpnessRow,
            focusIssueRow,
            subjectDetailRow,
            afPointRow,
            burstDecisionRow,
            clipSemanticMatchRow,
            clipSimilarityRow
        ]
        .compactMap { $0 }
    }

    private var sharpnessRow: MetadataRow? {
        guard let sharpness,
              let score = sharpness.score,
              score.isFinite,
              sharpness.maxScore.isFinite,
              sharpness.maxScore > 0
        else { return nil }

        let normalizedScore = min(max(score / sharpness.maxScore, 0), 1)
        return MetadataRow(
            id: "sharpness",
            label: "Sharpness",
            value: "\(sharpnessTitle(score: score, maxScore: sharpness.maxScore)) · \(percent(normalizedScore))",
        )
    }

    private var focusIssueRow: MetadataRow? {
        guard let focusFailureKind = sharpness?.breakdown?.focusFailureKind else { return nil }
        switch focusFailureKind {
        case .motionBlur, .missedFocus:
            return MetadataRow(
                id: "focusIssue",
                label: "Focus Issue",
                value: focusFailureKind.title,
            )

        case .none:
            return nil
        }
    }

    private var subjectDetailRow: MetadataRow? {
        guard let breakdown = sharpness?.breakdown,
              let subjectScore = breakdown.subjectScore,
              subjectScore.isFinite
        else { return nil }

        var value = percent(subjectScore)
        if let subject = breakdown.subjectLabel, !subject.isEmpty {
            value = "\(subject) · \(value)"
        }
        return MetadataRow(id: "subjectDetail", label: "Subject Detail", value: value)
    }

    private var afPointRow: MetadataRow? {
        let detail = sharpness?.breakdown?.afPointScore
        var parts: [String] = []
        if let point = normalizedAFPoint,
           point.x.isFinite,
           point.y.isFinite {
            let horizontalPosition = min(max(point.x, 0), 1)
            let verticalPosition = min(max(point.y, 0), 1)
            parts.append(
                "\(percent(Float(horizontalPosition))) across · \(percent(Float(verticalPosition))) down",
            )
        }
        if let detail, detail.isFinite {
            parts.append("\(percent(detail)) detail")
        }
        guard !parts.isEmpty else { return nil }
        return MetadataRow(
            id: "afPoint",
            label: "AF Point",
            value: parts.joined(separator: " · "),
            allowsMultipleLines: true,
        )
    }

    private var burstDecisionRow: MetadataRow? {
        guard let burstDecision else { return nil }
        var parts = ["#\(burstDecision.rank) of \(burstDecision.count)"]
        if burstDecision.isRecommendation {
            parts.insert("Suggested", at: 0)
        }
        if let score = burstDecision.score, score.isFinite {
            parts.append(percent(score))
        }
        return MetadataRow(
            id: "burstDecision",
            label: "Burst Decision",
            value: parts.joined(separator: " · "),
            allowsMultipleLines: true,
        )
    }

    private var clipSemanticMatchRow: MetadataRow? {
        guard let clipSemanticMatch, clipSemanticMatch.score.isFinite else { return nil }
        return MetadataRow(
            id: "clipSemanticMatch",
            label: "CLIP Match",
            value: "#\(clipSemanticMatch.rank) · \(decimal(clipSemanticMatch.score)) relative score",
            allowsMultipleLines: true,
        )
    }

    private var clipSimilarityRow: MetadataRow? {
        switch clipSimilarity {
        case .anchor:
            MetadataRow(
                id: "clipSimilarity",
                label: "CLIP Similarity",
                value: "Reference image",
            )

        case let .distance(distance) where distance.isFinite:
            MetadataRow(
                id: "clipSimilarity",
                label: "CLIP Similarity",
                value: "\(decimal(distance)) distance · lower is closer",
                allowsMultipleLines: true,
            )

        case .distance, .none:
            nil
        }
    }

    private func sharpnessTitle(score: Float, maxScore: Float) -> String {
        switch SharpnessLabel(score: score, maxScore: maxScore) {
        case .sharp: "Sharp"
        case .good: "Good"
        case .check: "Check"
        case .soft: "Soft"
        }
    }

    private func percent(_ value: Float) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func decimal(_ value: Float) -> String {
        value.formatted(.number.precision(.fractionLength(3)))
    }
}
