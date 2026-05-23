import SwiftUI

struct ComparisonImageState: Identifiable {
    let id: FileItem.ID
    var cgImage: CGImage?
    var nsImage: NSImage?
    var focusMask: CGImage?
    var sharpnessBreakdown: SharpnessBreakdown?
    var isLoading = false
}

struct SharpnessComparisonContext: Equatable {
    var rankTitle: String
    var deltaTitle: String?
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
            return SharpnessComparisonContext(rankTitle: rankTitle, deltaTitle: nil)
        }

        let subjectDelta = componentDelta(current.subjectScore, reference.subjectScore)
        let globalDelta = componentDelta(current.globalScore, reference.globalScore)
        let deltaTitle = [subjectDelta.map { "Subject \($0)" }, globalDelta.map { "Global \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")

        return SharpnessComparisonContext(
            rankTitle: rankTitle,
            deltaTitle: deltaTitle.isEmpty ? nil : deltaTitle,
        )
    }

    private nonisolated static func rankScore(
        for fileID: FileItem.ID,
        scores: [FileItem.ID: Float],
        breakdowns: [FileItem.ID: SharpnessBreakdown],
    ) -> Float {
        breakdowns[fileID]?.subjectScore ?? scores[fileID] ?? 0
    }

    private nonisolated static func componentDelta(_ current: Float?, _ reference: Float?) -> String? {
        guard let current, let reference else { return nil }
        let value = Int(((current - reference) * 100).rounded())
        return value >= 0 ? "+\(value)" : "\(value)"
    }
}
