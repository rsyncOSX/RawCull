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
            savedStates: savedStates(snapshots),
            groups: groups,
            files: files,
            catalog: catalog,
        )
    }

    /// Saved states keyed by signature. A malformed file may repeat a
    /// signature; the first entry wins instead of trapping.
    static func savedStates(
        _ snapshots: [BurstReviewStateSnapshot],
    ) -> [BurstGroupSignature: BurstReviewState] {
        Dictionary(snapshots.map { ($0.signature, $0.state) }, uniquingKeysWith: { first, _ in first })
    }

    /// Live states for every in-memory group whose members are all in `files`,
    /// including `.none`, so an unsaved un-mark also overrides a saved state.
    static func liveStates(
        states: [Int: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [BurstGroupSignature: BurstReviewState] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return Dictionary(groups.compactMap { group in
            guard group.fileIDs.allSatisfy({ filesByID[$0] != nil }),
                  let signature = signature(for: group, filesByID: filesByID, catalog: catalog)
            else { return nil }
            return (signature, states[group.id] ?? .none)
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Saved states with live in-memory states taking precedence.
    static func merged(
        saved snapshots: [BurstReviewStateSnapshot],
        live: [BurstGroupSignature: BurstReviewState],
    ) -> [BurstGroupSignature: BurstReviewState] {
        savedStates(snapshots).merging(live) { _, live in live }
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
