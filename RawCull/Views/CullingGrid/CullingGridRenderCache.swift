import Foundation
import RawCullCore

struct CullingGridVisibleBurstGroup: Identifiable, Equatable {
    let id: Int
    let files: [FileItem]
}

struct CullingGridRenderCacheKey: Hashable {
    let burstGroupsCount: Int
    let burstStructureHash: Int
    let filesCount: Int
    let filesStructureHash: Int
    let ratingFilter: GridRatingFilter
    let reviewQueueFilter: BurstReviewQueueFilter
    let scoresCount: Int
    let scoreRevision: Int
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

enum BurstGroupCleanViewPolicy {
    static let visibleLimit = 3

    static func visibleFiles(
        in files: [FileItem],
        rankedFileIDs: [FileItem.ID],
        isCollapsed: Bool,
    ) -> [FileItem] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var ordered = rankedFileIDs.compactMap { filesByID[$0] }
        let rankedIDs = Set(ordered.map(\.id))
        ordered.append(contentsOf: files.filter { !rankedIDs.contains($0.id) })

        guard isCollapsed, ordered.count > visibleLimit else { return ordered }
        return Array(ordered.prefix(visibleLimit))
    }
}
