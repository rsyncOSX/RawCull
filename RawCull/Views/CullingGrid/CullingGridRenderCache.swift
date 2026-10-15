import Foundation
import RawCullCore

struct CullingGridVisibleBurstGroup: Identifiable, Equatable {
    let id: Int
    let files: [FileItem]
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

enum BurstGroupFileOrderPolicy {
    static func orderedFiles(
        in files: [FileItem],
        rankedFileIDs: [FileItem.ID],
    ) -> [FileItem] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        var ordered = rankedFileIDs.compactMap { filesByID[$0] }
        let rankedIDs = Set(ordered.map(\.id))
        ordered.append(contentsOf: files.filter { !rankedIDs.contains($0.id) })
        return ordered
    }
}
