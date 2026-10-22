import Foundation
import RawCullCore

/// Membership-based persistence rules shared by live review and cached analysis.
nonisolated enum BurstReviewStateMapping {
    static func signature(
        for group: BurstGroup,
        filesByID: [UUID: FileItem],
        catalog: URL?,
    ) -> BurstGroupSignature? {
        BurstGroupSignature(files: group.fileIDs.compactMap { filesByID[$0] }, catalog: catalog)
    }

    static func snapshots(
        states: [Int: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [BurstReviewStateSnapshot] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return groups.compactMap { group in
            guard let state = states[group.id], state != .none,
                  let signature = signature(for: group, filesByID: filesByID, catalog: catalog)
            else { return nil }
            return BurstReviewStateSnapshot(signature: signature, state: state)
        }
    }

    static func restore(
        snapshots: [BurstReviewStateSnapshot],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        restore(
            savedStates: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.signature, $0.state) }),
            groups: groups,
            files: files,
            catalog: catalog,
        )
    }

    static func restore(
        savedStates: [BurstGroupSignature: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard let signature = signature(for: group, filesByID: filesByID, catalog: catalog),
                  let state = savedStates[signature], state != .none
            else { return nil }
            return (group.id, state)
        })
    }
}
