import Foundation
import RawCullCore

/// The measured and AI markers a burst frame shows. The burst workspace and the
/// AI Assessment window fill it in the same way, so each one shows what the other
/// one concluded.
nonisolated struct BurstFrameMarks: Equatable, Sendable {
    /// Highest measured sharpness in the burst.
    var isSharpest = false
    /// Mean AI rubric score (1–5) for an assessed frame.
    var aiScore: Double?
    /// The only assessed frame with the highest AI score.
    var isAITop = false

    /// The one entry with the highest value, or nil when fewer than two entries
    /// have values or the highest value is shared.
    static func leader<ID>(_ values: [(id: ID, value: Double)]) -> ID? {
        guard values.count > 1, let best = values.max(by: { $0.value < $1.value }),
              values.count(where: { $0.value == best.value }) == 1 else { return nil }
        return best.id
    }

    static func sharpestID(in files: [FileItem], scores: [FileItem.ID: Float]) -> FileItem.ID? {
        leader(files.compactMap { file in
            guard let score = scores[file.id], score.isFinite else { return nil }
            return (file.id, Double(score))
        })
    }

    static func formatted(_ score: Double) -> String {
        score.formatted(.number.precision(.fractionLength(1)))
    }
}

nonisolated extension AIAssessmentEntry.Frame {
    /// Mean of the AI rubric scores (1–5), or nil when the frame was not assessed.
    var aiScore: Double? {
        let scores = (outcome?.findings ?? [:]).values.compactMap(\.score)
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }
}

nonisolated extension AIAssessmentEntry {
    /// The assessed frame the AI scored highest, when one frame clearly leads.
    var aiTopFrameID: String? {
        BurstFrameMarks.leader(frames.compactMap { frame in frame.aiScore.map { (frame.id, $0) } })
    }
}

/// One frame's claim to be the best in the burst, by one method.
struct BurstFramePick: Identifiable {
    enum Kind { case aiTop, suggested, sharpest }
    let kind: Kind
    let fileName: String
    let select: () -> Void

    var id: Kind {
        kind
    }
}
