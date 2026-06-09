import RawCullCore
import SwiftUI

struct ComparisonImageState: Identifiable {
    let id: FileItem.ID
    var cgImage: CGImage?
    var nsImage: NSImage?
    var focusMask: CGImage?
    var sharpnessBreakdown: SharpnessBreakdown?
    var isLoading = false
}

struct ComparisonViewportInteractionState: Equatable {
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero
    var showFocusMask = false
    var showFocusPoints = false

    mutating func resetTransform() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

struct SharpnessComparisonContext: Equatable {
    var rankTitle: String
    var deltaParts: [SharpnessComparisonDeltaPart]
}

struct SharpnessComparisonDeltaPart: Equatable, Identifiable {
    var label: String
    var value: Int

    var id: String {
        label
    }

    var title: String {
        "\(label) \(formattedValue)"
    }

    private var formattedValue: String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

enum SharpnessComparisonSummary {
    nonisolated static func context(
        for fileID: FileItem.ID,
        fileIDs: [FileItem.ID],
        scores: [FileItem.ID: Float],
        breakdowns: [FileItem.ID: SharpnessBreakdown],
        winnerID: FileItem.ID?,
    ) -> SharpnessComparisonContext? {
        guard fileIDs.contains(fileID) else { return nil }
        let hasAnySubjectBreakdown = fileIDs.contains { breakdowns[$0]?.subjectScore != nil }
        let rankedIDs = fileIDs.sorted {
            rankScore(for: $0, scores: scores, breakdowns: breakdowns) >
                rankScore(for: $1, scores: scores, breakdowns: breakdowns)
        }
        guard let rankIndex = rankedIDs.firstIndex(of: fileID) else { return nil }

        let rankKind = hasAnySubjectBreakdown ? "subject sharpness" : "sharpness"
        let rankTitle = "#\(rankIndex + 1) of \(rankedIDs.count) in \(rankKind)"

        guard let winnerID,
              winnerID != fileID,
              let current = breakdowns[fileID],
              let reference = breakdowns[winnerID]
        else {
            return SharpnessComparisonContext(rankTitle: rankTitle, deltaParts: [])
        }

        let subjectDelta = componentDelta(current.subjectScore, reference.subjectScore)
        let globalDelta = componentDelta(current.globalScore, reference.globalScore)
        let deltaParts = [
            subjectDelta.map { SharpnessComparisonDeltaPart(label: "Subject", value: $0) },
            globalDelta.map { SharpnessComparisonDeltaPart(label: "Global", value: $0) }
        ]
        .compactMap { $0 }

        return SharpnessComparisonContext(
            rankTitle: rankTitle,
            deltaParts: deltaParts,
        )
    }

    private nonisolated static func rankScore(
        for fileID: FileItem.ID,
        scores: [FileItem.ID: Float],
        breakdowns: [FileItem.ID: SharpnessBreakdown],
    ) -> Float {
        breakdowns[fileID]?.subjectScore ?? scores[fileID] ?? 0
    }

    private nonisolated static func componentDelta(_ current: Float?, _ reference: Float?) -> Int? {
        guard let current, let reference else { return nil }
        return Int(((current - reference) * 100).rounded())
    }
}
