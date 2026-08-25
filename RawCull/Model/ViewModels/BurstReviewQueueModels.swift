import Foundation
import RawCullCore

enum BurstReviewQueueFilter: String, CaseIterable, Identifiable {
    case all
    case singleImages
    case needsReview
    case deferred
    case markedReviewed
    case reviewed

    var id: String {
        rawValue
    }
}

struct BurstReviewSummary: Equatable {
    var totalGroups: Int = 0
    var burstGroups: Int = 0
    var singleImages: Int = 0
    var needsReview: Int = 0
    var deferred: Int = 0
    var markedReviewed: Int = 0
    var completed: Int = 0
}

enum BurstReviewQueuePolicy {
    nonisolated static func effectiveState(for result: BurstAnalysisResult) -> BurstReviewState {
        switch result.reviewState {
        case .reviewed, .decisionApplied, .manualWinnerOverride:
            return .reviewed

        case .deferred:
            return .deferred

        case .none, .algorithmReviewed, .needsReview:
            // An algorithm recommendation is still waiting for the user to
            // review or apply it, even when confidence is high.
            return .needsReview
        }
    }

    nonisolated static func includes(_ result: BurstAnalysisResult, filter: BurstReviewQueueFilter) -> Bool {
        return switch filter {
        case .all:
            true

        case .singleImages:
            false

        case .needsReview:
            effectiveState(for: result) == .needsReview

        case .deferred:
            effectiveState(for: result) == .deferred

        case .markedReviewed:
            result.reviewState == .reviewed

        case .reviewed:
            effectiveState(for: result) == .reviewed
        }
    }

    nonisolated static func summary(
        for groups: some Sequence<BurstGroup>,
        resultsByGroupID: [Int: BurstAnalysisResult],
    ) -> BurstReviewSummary {
        groups.reduce(into: BurstReviewSummary()) { summary, group in
            summary.totalGroups += 1

            guard group.fileIDs.count > 1 else {
                summary.singleImages += 1
                return
            }

            summary.burstGroups += 1

            guard let result = resultsByGroupID[group.id] else {
                // The group list is authoritative. A missing analysis result
                // must remain visible as pending instead of vanishing from all
                // workflow counts.
                summary.needsReview += 1
                return
            }

            if result.reviewState == .reviewed {
                summary.markedReviewed += 1
            }

            switch effectiveState(for: result) {
            case .needsReview:
                summary.needsReview += 1

            case .deferred:
                summary.deferred += 1

            case .reviewed:
                summary.completed += 1

            case .none, .algorithmReviewed, .manualWinnerOverride, .decisionApplied:
                assertionFailure("effectiveState(for:) must return a workflow state")
            }
        }
    }
}
