import CoreGraphics
import PhotoAnalysisKit
@testable import RawCull
import Testing

@Suite("Zoom culling metadata")
@MainActor
struct ZoomCullingMetadataTests {
    @Test
    func `rows are omitted when decision evidence is absent`() {
        let metadata = ZoomCullingMetadata(
            sharpness: nil,
            normalizedAFPoint: nil,
            burstDecision: nil,
            similarity: nil,
        )

        #expect(metadata.decisionRows.isEmpty)
    }

    @Test
    func `only present decision evidence creates rows`() {
        let metadata = ZoomCullingMetadata(
            sharpness: nil,
            normalizedAFPoint: CGPoint(x: 0.25, y: 0.75),
            burstDecision: nil,
            similarity: nil,
        )

        #expect(metadata.decisionRows.map { $0.id } == ["afPoint"])
    }

    @Test
    func `vital culling and Vision similarity evidence create concise rows`() {
        let breakdown = RawCull.SharpnessBreakdown(
            finalScore: 0.8,
            globalScore: 0.7,
            subjectScore: 0.9,
            afPointScore: 0.85,
            blurGateSigma: 1.2,
            subjectLabel: "Bird",
            subjectConfidence: 0.95,
            focusFailureKind: PhotoAnalysisKit.FocusFailureKind.missedFocus,
        )
        let metadata = ZoomCullingMetadata(
            sharpness: ZoomCullingMetadata.Sharpness(
                score: 0.8,
                maxScore: 1,
                breakdown: breakdown,
            ),
            normalizedAFPoint: CGPoint(x: 0.4, y: 0.6),
            burstDecision: ZoomCullingMetadata.BurstDecision(
                rank: 1,
                count: 5,
                score: 0.88,
                isRecommendation: true,
            ),
            similarity: .distance(0.12),
        )

        #expect(metadata.decisionRows.map { $0.id } == [
            "sharpness",
            "focusIssue",
            "subjectDetail",
            "afPoint",
            "burstDecision",
            "similarity"
        ])
    }
}
