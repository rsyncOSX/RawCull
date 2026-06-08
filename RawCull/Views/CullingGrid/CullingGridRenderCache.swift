import Foundation
import RawCullCore

struct CullingGridVisibleBurstGroup: Identifiable, Equatable {
    let id: Int
    let files: [FileItem]
}

struct CullingGridRenderCacheKey: Hashable {
    // periphery:ignore
    let burstGroupsCount: Int
    // periphery:ignore
    let burstStructureHash: Int
    // periphery:ignore
    let filesCount: Int
    // periphery:ignore
    let filesFirstID: UUID?
    // periphery:ignore
    let filesLastID: UUID?
    // periphery:ignore
    let ratingFilter: GridRatingFilter
    // periphery:ignore
    let reviewQueueFilter: BurstReviewQueueFilter
    // periphery:ignore
    let scoresCount: Int

    init(
        burstGroups: [BurstGroup],
        files: [FileItem],
        ratingFilter: GridRatingFilter,
        reviewQueueFilter: BurstReviewQueueFilter,
        scoresCount: Int,
        burstAnalysisResults: [Int: BurstAnalysisResult],
    ) {
        var structureHasher = Hasher()
        for group in burstGroups {
            structureHasher.combine(group.id)
            structureHasher.combine(group.fileIDs.count)
            if let result = burstAnalysisResults[group.id] {
                structureHasher.combine(result.recommendedFileID)
                structureHasher.combine(result.reviewState.rawValue)
            }
        }

        self.burstGroupsCount = burstGroups.count
        self.burstStructureHash = structureHasher.finalize()
        self.filesCount = files.count
        self.filesFirstID = files.first?.id
        self.filesLastID = files.last?.id
        self.ratingFilter = ratingFilter
        self.reviewQueueFilter = reviewQueueFilter
        self.scoresCount = scoresCount
    }
}

struct CullingGridRenderCache {
    var visibleBurstGroups: [CullingGridVisibleBurstGroup] = []
    var bestInGroup: [Int: BestInGroupInfo] = [:]
    var hasSharpnessScoresSnapshot = false

    static func rebuild(
        files: [FileItem],
        burstGroups: [BurstGroup],
        scores: [UUID: Float],
        maxScore: Float,
        burstAnalysisResults: [Int: BurstAnalysisResult],
    ) -> CullingGridRenderCache {
        let lookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })

        var visibleGroups: [CullingGridVisibleBurstGroup] = []
        visibleGroups.reserveCapacity(burstGroups.count)
        var bestInGroup: [Int: BestInGroupInfo] = [:]

        for group in burstGroups {
            let visible = group.fileIDs.compactMap { lookup[$0] }
            guard !visible.isEmpty else { continue }
            visibleGroups.append(CullingGridVisibleBurstGroup(id: group.id, files: visible))

            if let result = burstAnalysisResults[group.id],
               result.reviewState == .manualWinnerOverride,
               let winnerID = result.recommendedFileID,
               let winner = visible.first(where: { $0.id == winnerID }) {
                bestInGroup[group.id] = RawCullViewModel.bestInGroupInfo(
                    file: winner,
                    scores: scores,
                    maxScore: maxScore,
                    isManualWinner: true,
                )
            } else if let info = RawCullViewModel.bestInGroupInfo(
                files: visible,
                scores: scores,
                maxScore: maxScore,
            ) {
                bestInGroup[group.id] = info
            }
        }

        return CullingGridRenderCache(
            visibleBurstGroups: visibleGroups,
            bestInGroup: bestInGroup,
            hasSharpnessScoresSnapshot: !scores.isEmpty,
        )
    }
}
