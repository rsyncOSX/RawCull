import Foundation
import Observation
import RawCullCore

/// Application-lifetime review decisions, independent of image and viewport state.
@MainActor
@Observable
final class BurstReviewSessionModel {
    private(set) var results: [Int: BurstAnalysisResult] = [:] {
        didSet { contentRevision &+= 1 }
    }
    private(set) var contentRevision: UInt64 = 0
    private(set) var reviewStates: [Int: BurstReviewState] = [:]
    var queueFilter: BurstReviewQueueFilter = .all
    var activeComparisonGroupID: Int?
    var lastUndoEntry: BurstUndoEntry?

    func applyAnalysis(rankings: [BurstAnalysisResult], restoredReviewStates: [Int: BurstReviewState]) {
        reviewStates = restoredReviewStates
        replaceRankings(Dictionary(uniqueKeysWithValues: rankings.map { ($0.groupID, $0) }))
    }

    func replaceRankings(_ rankings: [Int: BurstAnalysisResult]) {
        results = rankings
    }

    /// Regrouping restores explicit workflow states before recomputing rankings.
    func restoreReviewStates(_ states: [Int: BurstReviewState]) {
        reviewStates = states
    }

    func applyManualWinnerOverride(groupID: Int, winnerID: UUID) {
        reviewStates[groupID] = .manualWinnerOverride
        guard var result = results[groupID] else { return }
        result.recommendedFileID = winnerID
        result.secondBestFileID = result.candidates.first { $0.fileID != winnerID }?.fileID
        result.reviewState = .manualWinnerOverride
        results[groupID] = result
    }

    /// Returns whether the caller should persist the decision. Manual overrides
    /// retain their existing result and do not trigger another persistence request.
    func markDecisionApplied(groupID: Int, scopedGroups: [BurstGroup]) -> Bool {
        if results[groupID]?.reviewState == .manualWinnerOverride {
            reviewStates[groupID] = .manualWinnerOverride
            return false
        }
        setReviewState(.decisionApplied, groupID: groupID, scopedGroups: scopedGroups)
        return true
    }

    func synchronizeResultReviewStateAfterUndo(groupID: Int) {
        guard var result = results[groupID] else { return }
        result.reviewState = reviewStates[groupID] ?? .none
        results[groupID] = result
    }

    func filteredGroups(in scopedGroups: [BurstGroup]) -> [BurstGroup] {
        switch queueFilter {
        case .all:
            return scopedGroups.filter { $0.fileIDs.count > 1 }

        case .singleImages:
            return scopedGroups.filter { $0.fileIDs.count == 1 }

        case .needsReview, .deferred, .markedReviewed, .reviewed:
            break
        }

        return scopedGroups.filter { group in
            guard group.fileIDs.count > 1 else { return false }
            guard let result = results[group.id] else {
                return queueFilter == .needsReview
            }
            return BurstReviewQueuePolicy.includes(result, filter: queueFilter)
        }
    }

    func reviewState(groupID: Int, scopedGroups: [BurstGroup]) -> BurstReviewState {
        guard groupID == -1 else {
            return reviewStates[groupID] ?? results[groupID]?.reviewState ?? .none
        }
        let groups = scopedGroups.filter { $0.fileIDs.count == 1 }
        guard let first = groups.first else { return .none }
        let state = reviewStates[first.id] ?? .none
        return groups.allSatisfy { (reviewStates[$0.id] ?? .none) == state } ? state : .none
    }

    func setReviewState(_ state: BurstReviewState, groupID: Int, scopedGroups: [BurstGroup]) {
        if groupID == -1 {
            for group in scopedGroups where group.fileIDs.count == 1 {
                setReviewState(state, groupID: group.id, scopedGroups: scopedGroups)
            }
            return
        }
        switch state {
        case .none:
            reviewStates.removeValue(forKey: groupID)
        default:
            reviewStates[groupID] = state
        }
        if var result = results[groupID] {
            result.reviewState = state
            results[groupID] = result
        }
    }

    func reset() {
        results = [:]
        reviewStates = [:]
        queueFilter = .all
        activeComparisonGroupID = nil
        lastUndoEntry = nil
    }
}
