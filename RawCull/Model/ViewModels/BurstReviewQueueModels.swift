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

struct BurstReviewQueueCounts: Equatable {
    var needsReview: Int = 0
    var deferred: Int = 0
    var reviewed: Int = 0
}

struct BurstGroupsHomeCounts: Equatable {
    var singleImages: Int = 0
    var deferred: Int = 0
    var markedReviewed: Int = 0
    var needsReview: Int = 0
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
        guard result.fileIDs.count > 1 else { return false }
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

    nonisolated static func counts(for results: some Sequence<BurstAnalysisResult>) -> BurstReviewQueueCounts {
        results.reduce(into: BurstReviewQueueCounts()) { counts, result in
            guard result.fileIDs.count > 1 else { return }
            switch effectiveState(for: result) {
            case .needsReview:
                counts.needsReview += 1

            case .deferred:
                counts.deferred += 1

            case .reviewed:
                counts.reviewed += 1

            case .none, .algorithmReviewed, .manualWinnerOverride, .decisionApplied:
                assertionFailure("effectiveState(for:) must return a workflow state")
            }
        }
    }
}
