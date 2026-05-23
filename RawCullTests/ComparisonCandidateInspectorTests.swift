import CoreGraphics
import Foundation
@testable import RawCull
import Testing

@Suite("Comparison candidate inspector")
@MainActor
struct ComparisonCandidateInspectorTests {
    @Test(.tags(.smoke))
    func `exif footer omits missing fields and preserves display order`() {
        let summary = ExifSummary.make(from: ExifMetadata(
            shutterSpeed: "1/1000",
            focalLength: "24.0mm",
            aperture: "f/2.8",
            apertureValue: 2.8,
            iso: "ISO 800",
            isoValue: 800,
            camera: "ILCE-1",
            lensModel: nil,
            rawFileType: "ARW",
            rawSizeClass: "L",
            pixelWidth: 8640,
            pixelHeight: 5760,
        ))

        #expect(summary.exposureParts == ["1/1000", "f/2.8", "ISO 800"])
        #expect(summary.gearParts == ["24.0mm", "ILCE-1"])
        #expect(summary.detailRows.map(\.label) == [
            "Camera",
            "Focal Length",
            "Aperture",
            "Shutter Speed",
            "ISO",
            "RAW Type",
            "Dimensions",
        ])
    }

    @Test(.tags(.smoke))
    func `candidate context resolves selected rank saliency scores and focus points`() throws {
        let first = comparisonInspectorFile("first.ARW", seconds: 0)
        let second = comparisonInspectorFile("second.ARW", seconds: 1)
        let result = BurstAnalysisResult(
            groupID: 0,
            fileIDs: [first.id, second.id],
            candidates: [
                comparisonCandidate(fileID: second.id, score: 0.9),
                comparisonCandidate(fileID: first.id, score: 0.7),
            ],
            recommendedFileID: second.id,
            secondBestFileID: first.id,
            confidence: .high,
            reviewState: .algorithmReviewed,
            isSafeForOneClickCulling: true,
            reasons: ["Sharpest candidate leads"],
            cautions: ["Top two are close"],
        )
        let breakdown = SharpnessBreakdown(
            finalScore: 0.8,
            globalScore: 0.7,
            subjectScore: 0.8,
            afPointScore: 0.6,
            blurGateSigma: 0.03,
            subjectLabel: "bird",
            subjectConfidence: 0.9,
            focusFailureKind: .none,
        )

        let context = try #require(CandidateInspectorContext.make(
            selectedFile: first,
            result: result,
            files: [first, second],
            saliencyInfo: [first.id: SaliencyInfo(subjectLabel: "bird")],
            sharpnessScores: [first.id: 0.8],
            sharpnessBreakdowns: [first.id: breakdown],
            focusPoints: nil,
            rating: 2,
        ))

        #expect(context.rank == 2)
        #expect(context.saliencyLabel == "bird")
        #expect(context.sharpnessScore == 0.8)
        #expect(context.hasFocusPoints)
        #expect(context.rankRows.map(\.fileID) == [second.id, first.id])
        #expect(context.rankRows[0].isRecommended)
        #expect(context.rankRows[1].isSecondBest)
        #expect(context.rankRows[1].isSelected)
        #expect(context.groupReasons == ["Sharpest candidate leads"])
        #expect(context.groupCautions == ["Top two are close"])
    }

    @Test(.tags(.smoke))
    func `finalist focus uses top two ranked candidates without mutating source ids`() {
        let ids = [UUID(), UUID(), UUID()]
        let result = BurstAnalysisResult(
            groupID: 0,
            fileIDs: ids,
            candidates: [
                comparisonCandidate(fileID: ids[2], score: 0.9),
                comparisonCandidate(fileID: ids[0], score: 0.8),
                comparisonCandidate(fileID: ids[1], score: 0.7),
            ],
            recommendedFileID: ids[2],
            secondBestFileID: ids[0],
            confidence: .medium,
            reviewState: .algorithmReviewed,
            isSafeForOneClickCulling: false,
            reasons: [],
            cautions: [],
        )

        #expect(ComparisonFinalistFocus.focusedIDs(from: result) == [ids[2], ids[0]])
        #expect(result.fileIDs == ids)
    }

    @Test(.tags(.smoke))
    func `finalist focus falls back to file ids when candidates are missing`() {
        let ids = [UUID(), UUID(), UUID()]
        let result = BurstAnalysisResult(
            groupID: 0,
            fileIDs: ids,
            candidates: [],
            recommendedFileID: nil,
            secondBestFileID: nil,
            confidence: .low,
            reviewState: .none,
            isSafeForOneClickCulling: false,
            reasons: [],
            cautions: [],
        )

        #expect(ComparisonFinalistFocus.focusedIDs(from: result) == Array(ids.prefix(2)))
    }
}

private func comparisonInspectorFile(_ name: String, seconds: TimeInterval) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: seconds),
        exifData: ExifMetadata(
            shutterSpeed: "1/1000",
            focalLength: "24.0mm",
            aperture: "f/2.8",
            apertureValue: 2.8,
            iso: "ISO 800",
            isoValue: 800,
            camera: "ILCE-1",
            lensModel: "FE 24-70mm",
            rawFileType: nil,
            rawSizeClass: nil,
            pixelWidth: nil,
            pixelHeight: nil,
        ),
        afFocusNormalized: CGPoint(x: 0.5, y: 0.5),
    )
}

private func comparisonCandidate(fileID: UUID, score: Float) -> BurstCandidateScore {
    BurstCandidateScore(
        fileID: fileID,
        overallScore: score,
        sharpnessComponent: score,
        focusPointComponent: 0.7,
        saliencyComponent: 0.6,
        metadataComponent: 0.8,
        confidence: .medium,
        reasons: ["Sharpness measured"],
        cautions: [],
    )
}
