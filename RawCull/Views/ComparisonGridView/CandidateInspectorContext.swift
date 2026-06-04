import Foundation
import RawCullCore

struct ExifSummary: Equatable {
    var exposureParts: [String]
    var gearParts: [String]
    var detailRows: [ExifDetailRow]

    var hasFooterContent: Bool {
        !exposureParts.isEmpty || !gearParts.isEmpty
    }

    static func make(from exif: ExifMetadata?) -> Self {
        guard let exif else {
            return ExifSummary(exposureParts: [], gearParts: [], detailRows: [])
        }

        var exposureParts: [String] = []
        append(exif.shutterSpeed, to: &exposureParts)
        append(exif.aperture, to: &exposureParts)
        append(exif.iso, to: &exposureParts)

        var gearParts: [String] = []
        append(exif.focalLength, to: &gearParts)
        append(exif.lensModel, to: &gearParts)
        append(exif.camera, to: &gearParts)

        var detailRows: [ExifDetailRow] = []
        appendRow("Camera", exif.camera, to: &detailRows)
        appendRow("Lens", exif.lensModel, to: &detailRows)
        appendRow("Focal Length", exif.focalLength, to: &detailRows)
        appendRow("Aperture", exif.aperture, to: &detailRows)
        appendRow("Shutter Speed", exif.shutterSpeed, to: &detailRows)
        appendRow("ISO", exif.iso, to: &detailRows)
        appendRow("RAW Type", exif.rawFileType, to: &detailRows)
        if let w = exif.pixelWidth, let h = exif.pixelHeight {
            let mp = Double(w * h) / 1_000_000
            let sizeClass = exif.rawSizeClass.map { " (\($0))" } ?? ""
            detailRows.append(ExifDetailRow(
                label: "Dimensions",
                value: String(format: "%d x %d  %.1f MP%@", w, h, mp, sizeClass),
            ))
        }

        return ExifSummary(
            exposureParts: exposureParts,
            gearParts: gearParts,
            detailRows: detailRows,
        )
    }

    private static func append(_ value: String?, to parts: inout [String]) {
        guard let value, !value.isEmpty else { return }
        parts.append(value)
    }

    private static func appendRow(
        _ label: String,
        _ value: String?,
        to rows: inout [ExifDetailRow],
    ) {
        guard let value, !value.isEmpty else { return }
        rows.append(ExifDetailRow(label: label, value: value))
    }
}

struct ExifDetailRow: Equatable, Identifiable {
    var label: String
    var value: String

    var id: String {
        label
    }
}

struct CandidateRankRow: Equatable, Identifiable {
    var rank: Int
    var fileID: FileItem.ID
    var fileName: String
    var score: Float
    var isRecommended: Bool
    var isSecondBest: Bool
    var isManualWinner: Bool
    var isSelected: Bool

    var id: FileItem.ID {
        fileID
    }
}

struct CandidateInspectorContext {
    var file: FileItem
    var candidate: BurstCandidateScore
    var rank: Int
    var confidence: BurstDecisionConfidence
    var rating: Int
    var saliencyLabel: String?
    var sharpnessScore: Float?
    var sharpnessBreakdown: SharpnessBreakdown?
    var hasFocusPoints: Bool
    var exifSummary: ExifSummary
    var rankRows: [CandidateRankRow]
    var groupReasons: [String]
    var groupCautions: [String]

    static func make(
        selectedFile: FileItem?,
        result: BurstAnalysisResult?,
        files: [FileItem],
        saliencyInfo: [FileItem.ID: SaliencyInfo],
        sharpnessScores: [FileItem.ID: Float],
        sharpnessBreakdowns: [FileItem.ID: SharpnessBreakdown],
        focusPoints: [FocusPointsModel]?,
        rating: Int,
    ) -> Self? {
        guard let selectedFile,
              let result,
              let candidateIndex = result.candidates.firstIndex(where: { $0.fileID == selectedFile.id })
        else { return nil }

        let candidate = result.candidates[candidateIndex]
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let rankRows = result.candidates.enumerated().map { index, candidate in
            CandidateRankRow(
                rank: index + 1,
                fileID: candidate.fileID,
                fileName: filesByID[candidate.fileID]?.name ?? "Unknown file",
                score: candidate.overallScore,
                isRecommended: result.recommendedFileID == candidate.fileID,
                isSecondBest: result.secondBestFileID == candidate.fileID,
                isManualWinner: result.reviewState == .manualWinnerOverride
                    && result.recommendedFileID == candidate.fileID,
                isSelected: selectedFile.id == candidate.fileID,
            )
        }

        return CandidateInspectorContext(
            file: selectedFile,
            candidate: candidate,
            rank: candidateIndex + 1,
            confidence: result.confidence,
            rating: rating,
            saliencyLabel: saliencyInfo[selectedFile.id]?.subjectLabel,
            sharpnessScore: sharpnessScores[selectedFile.id],
            sharpnessBreakdown: sharpnessBreakdowns[selectedFile.id],
            hasFocusPoints: focusPointsAvailable(for: selectedFile, focusPoints: focusPoints),
            exifSummary: ExifSummary.make(from: selectedFile.exifData),
            rankRows: rankRows,
            groupReasons: result.reasons,
            groupCautions: result.cautions,
        )
    }

    private static func focusPointsAvailable(
        for file: FileItem,
        focusPoints: [FocusPointsModel]?,
    ) -> Bool {
        guard let focusPoints else { return file.afFocusNormalized != nil }
        return focusPoints.contains { model in
            model.sourceFile == file.name && !model.focusPoints.isEmpty
        } || file.afFocusNormalized != nil
    }
}

enum ComparisonFinalistFocus {
    nonisolated static func focusedIDs(from result: BurstAnalysisResult?) -> [FileItem.ID] {
        guard let result else { return [] }
        var focusedIDs: [FileItem.ID] = []
        append(result.recommendedFileID, to: &focusedIDs)
        append(result.secondBestFileID, to: &focusedIDs)
        if !focusedIDs.isEmpty {
            return focusedIDs
        }

        let candidateIDs = result.candidates.prefix(2).map(\.fileID)
        if !candidateIDs.isEmpty {
            return Array(candidateIDs)
        }
        return Array(result.fileIDs.prefix(2))
    }

    private nonisolated static func append(_ id: FileItem.ID?, to ids: inout [FileItem.ID]) {
        guard let id, !ids.contains(id) else { return }
        ids.append(id)
    }
}
