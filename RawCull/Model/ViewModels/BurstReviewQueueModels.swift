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
        if result.reviewState != .none, result.reviewState != .algorithmReviewed {
            return result.reviewState
        }
        return needsReview(result) ? .needsReview : .reviewed
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
            switch result.reviewState {
            case .reviewed, .decisionApplied, .manualWinnerOverride:
                true

            default:
                false
            }
        }
    }

    nonisolated static func counts(for results: some Sequence<BurstAnalysisResult>) -> BurstReviewQueueCounts {
        results.reduce(into: BurstReviewQueueCounts()) { counts, result in
            guard result.fileIDs.count > 1 else { return }
            switch result.reviewState {
            case .needsReview:
                counts.needsReview += 1

            case .deferred:
                counts.deferred += 1

            case .reviewed, .decisionApplied, .manualWinnerOverride:
                counts.reviewed += 1

            case .none, .algorithmReviewed:
                if needsReview(result) {
                    counts.needsReview += 1
                }
            }
        }
    }

    private nonisolated static func needsReview(_ result: BurstAnalysisResult) -> Bool {
        guard result.reviewState != .decisionApplied,
              result.reviewState != .manualWinnerOverride
        else { return false }

        return result.reviewState == .needsReview
            || result.confidence != .high
            || !result.cautions.isEmpty
            || result.recommendedFileID == nil
            || !result.isSafeForOneClickCulling
    }
}
