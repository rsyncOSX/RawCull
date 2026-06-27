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
    let filesStructureHash: Int
    // periphery:ignore
    let ratingFilter: GridRatingFilter
    // periphery:ignore
    let reviewQueueFilter: BurstReviewQueueFilter
    // periphery:ignore
    let scoresCount: Int
    // periphery:ignore
    let scoreRevision: Int
    // periphery:ignore
    let maxScore: Float

    init(
        burstGroups: [BurstGroup],
        files: [FileItem],
        ratingFilter: GridRatingFilter,
        reviewQueueFilter: BurstReviewQueueFilter,
        scoresCount: Int,
        scoreRevision: Int,
        maxScore: Float,
        burstAnalysisResults: [Int: BurstAnalysisResult],
    ) {
        var structureHasher = Hasher()
        for group in burstGroups {
            structureHasher.combine(group.id)
            structureHasher.combine(group.fileIDs.count)
            for fileID in group.fileIDs {
                structureHasher.combine(fileID)
            }
            if let result = burstAnalysisResults[group.id] {
                structureHasher.combine(result.recommendedFileID)
                structureHasher.combine(result.reviewState.rawValue)
            }
        }
        var filesHasher = Hasher()
        for file in files {
            filesHasher.combine(file.id)
        }

        self.burstGroupsCount = burstGroups.count
        self.burstStructureHash = structureHasher.finalize()
        self.filesCount = files.count
        self.filesStructureHash = filesHasher.finalize()
        self.ratingFilter = ratingFilter
        self.reviewQueueFilter = reviewQueueFilter
        self.scoresCount = scoresCount
        self.scoreRevision = scoreRevision
        self.maxScore = maxScore
    }
}

struct CullingGridRenderCache {
    var visibleBurstGroups: [CullingGridVisibleBurstGroup] = []
    var hasSharpnessScoresSnapshot = false

    static func rebuild(
        files: [FileItem],
        burstGroups: [BurstGroup],
        scores: [UUID: Float],
    ) -> CullingGridRenderCache {
        let lookup = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })

        var visibleGroups: [CullingGridVisibleBurstGroup] = []
        visibleGroups.reserveCapacity(burstGroups.count)

        for group in burstGroups {
            let visible = group.fileIDs.compactMap { lookup[$0] }
            guard !visible.isEmpty else { continue }
            visibleGroups.append(CullingGridVisibleBurstGroup(id: group.id, files: visible))
        }

        return CullingGridRenderCache(
            visibleBurstGroups: visibleGroups,
            hasSharpnessScoresSnapshot: !scores.isEmpty,
        )
    }
}
