import CoreGraphics
import Foundation

nonisolated struct ReviewNormalizedPoint: Codable, Sendable {
    let x: CGFloat
    let y: CGFloat
}

nonisolated struct ReviewPrimarySubjectCue: Codable, Sendable {
    let concept: String
    let location: ReviewNormalizedPoint?
    let reason: String
}

nonisolated struct ReviewSubjectRelevance: Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case primaryCandidate, equallyImportantCandidate, contextual, unassigned }
    let role: Role
    let provenance: String
    let uncertainty: String
    var rank: Int {
        switch role { case .primaryCandidate: 0
        case .equallyImportantCandidate: 1
        case .unassigned: 2
        case .contextual: 3 }
    }
}

nonisolated struct ReviewRegionOmission: Codable, Sendable {
    enum Reason: String, Codable, Sendable { case budgetDepthPolicy, geometryFailure, ambiguousAnatomy, contextualPriority, unavailableInput }
    let regionID: ReviewRegionID
    let subjectID: ReviewSubjectID?
    let reason: Reason
    let detail: String
}

nonisolated enum ReviewSubjectPriority {
    static let version = "declared-subject-priority-v1"
    static func assign(_ subjects: [ReviewSubjectRecord], cues: [ReviewPrimarySubjectCue], contextual: [String],
                       masks: [ReviewSubjectID: CGImage], provenance: String) throws -> [ReviewSubjectRecord] {
        var roles: [ReviewSubjectID: ReviewSubjectRelevance] = [:]
        for cue in cues {
            let matching = subjects.filter { $0.concept == cue.concept }
            let pointed: [ReviewSubjectRecord]
            if let point = cue.location {
                guard point.x.isFinite, point.y.isFinite, (0 ... 1).contains(point.x), (0 ... 1).contains(point.y) else { throw ReviewImageError.invalidGeometry }
                pointed = try matching.filter { subject in
                    guard let mask = masks[subject.id] else { return false }
                    let foreground = try SubjectMaskForeground.decode(mask, width: mask.width, height: mask.height)
                    let x = min(mask.width - 1, Int(point.x * CGFloat(mask.width)))
                    let y = min(mask.height - 1, Int(point.y * CGFloat(mask.height)))
                    return foreground.pixels[y * mask.width + x] > 16
                }
            } else {
                pointed = matching
            }
            for subject in pointed.isEmpty ? matching : pointed {
                let role: ReviewSubjectRelevance.Role = pointed.count == 1 ? .primaryCandidate : .equallyImportantCandidate
                roles[subject.id] = .init(role: role, provenance: provenance + ": " + cue.reason,
                                          uncertainty: role == .primaryCandidate ? "Overview nomination; photographic importance is unverified" : "Ambiguous or equally important instances; stable ID order shares priority")
            }
        }
        return subjects.map { subject in
            var value = subject
            value.relevance = roles[subject.id] ?? .init(role: contextual.contains(subject.concept) ? .contextual : .unassigned,
                                                         provenance: provenance,
                                                         uncertainty: contextual.contains(subject.concept) ? "Overview declared contextual; importance unverified" : "No supported main-subject assignment")
            return value
        }.sorted {
            let left = $0.relevance?.rank ?? 2, right = $1.relevance?.rank ?? 2
            return left == right ? $0.id.rawValue < $1.id.rawValue : left < right
        }
    }
}
