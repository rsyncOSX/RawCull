import Foundation
import RawCullCore

struct CullingGridProjectionKey: Equatable {
    let contentRevision: UInt64
    let ratingRevision: UInt64
    let reviewRevision: UInt64
    let similarityRevision: UInt64
    let saliencyRevision: UInt64
    let sourceURL: URL?
    let ratingFilter: GridRatingFilter
    let reviewQueueFilter: BurstReviewQueueFilter
    let showsBurstGroups: Bool
    let hasSharpnessScores: Bool
}

struct CullingGridProjection {
    let key: CullingGridProjectionKey
    let files: [FileItem]
    let fileIDs: [FileItem.ID]
    let groups: [CullingGridVisibleBurstGroup]
    let groupNumbers: [Int: Int]
    let selectionFiles: [FileItem]
    let selectionIDs: [FileItem.ID]
    let badges: [BatchBadgeSelectionItem]
}

extension RawCullViewModel {
    /// Revisions are advanced at mutation sites. Reading this key never hashes
    /// catalog membership or reconstructs a semantic selection set.
    func cullingGridProjection(ratingFilter: GridRatingFilter) -> CullingGridProjection {
        let key = CullingGridProjectionKey(
            contentRevision: catalog.gridRevision,
            ratingRevision: ratings.revision,
            reviewRevision: burstWorkflow.burstReviewSession.contentRevision,
            similarityRevision: similarityModel.gridContentRevision,
            saliencyRevision: sharpnessModel.saliencyRevision,
            sourceURL: catalog.selectedSource?.url,
            ratingFilter: ratingFilter,
            reviewQueueFilter: burstWorkflow.burstReviewQueueFilter,
            showsBurstGroups: navigation.showsBurstGroups,
            hasSharpnessScores: !sharpnessModel.scores.isEmpty,
        )
        if let cached = gridProjectionCache, cached.key == key {
            return cached
        }
        let visibleFiles: [FileItem] = switch ratingFilter {
        case .all:
            catalog.filteredFiles

        case .unrated:
            catalog.selectedSource == nil ? catalog.filteredFiles : catalog.filteredFiles.filter { ratings.ratingCache[$0.name] == nil }

        case let .rating(value):
            catalog.filteredFiles.filter { ratings.ratingCache[$0.name] == value }
        }
        let cache = CullingGridRenderCache.rebuild(
            files: visibleFiles, burstGroups: burstWorkflow.filteredBurstGroupsForReviewQueue,
            scores: sharpnessModel.scores,
        )
        let groups: [CullingGridVisibleBurstGroup]
        if burstWorkflow.burstReviewQueueFilter == .singleImages {
            let singleFiles = cache.visibleBurstGroups.flatMap(\.files)
            groups = singleFiles.isEmpty ? [] : [CullingGridVisibleBurstGroup(id: -1, files: singleFiles)]
        } else {
            groups = cache.visibleBurstGroups.map { group in
                CullingGridVisibleBurstGroup(id: group.id, files: BurstGroupFileOrderPolicy.orderedFiles(
                    in: group.files, rankedFileIDs: burstWorkflow.burstAnalysisResults[group.id]?.candidates.map(\.fileID) ?? [],
                ))
            }
        }
        let selectionFiles = key.showsBurstGroups ? groups.flatMap(\.files) : visibleFiles
        let projection = CullingGridProjection(
            key: key, files: visibleFiles, fileIDs: visibleFiles.map(\.id), groups: groups,
            groupNumbers: Dictionary(similarityModel.burstGroups.enumerated().map { ($0.element.id, $0.offset + 1) },
                                     uniquingKeysWith: { first, _ in first }),
            selectionFiles: selectionFiles, selectionIDs: selectionFiles.map(\.id),
            badges: CullingGridSelectionCoordinator.badgeSelectionItems(
                visibleFiles: selectionFiles, burstGroupLookup: similarityModel.burstGroupLookup,
                burstAnalysisResults: burstWorkflow.burstAnalysisResults, saliencyInfo: sharpnessModel.saliencyInfo,
            ),
        )
        // Memoization is not presentation state; cache writes are observation-ignored.
        gridProjectionCache = projection
        gridProjectionBuildCount += 1
        return projection
    }
}
