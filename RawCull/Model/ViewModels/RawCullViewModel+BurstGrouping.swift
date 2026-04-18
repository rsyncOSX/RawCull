//
//  RawCullViewModel+BurstGrouping.swift
//  RawCull
//

import Foundation

/// Precomputed "best frame" info for a burst group — consumed by the
/// grid's burst-section header so the header body does no scoring math
/// on redraw.
struct BestInGroupInfo: Equatable {
    /// let fileID: UUID
    let fileName: String
    /// Percentage of `maxScore`, or nil when scores are missing or maxScore ≤ 0.
    let percent: Int?
}

extension RawCullViewModel {
    // MARK: - Combined index + group action

    /// Index all files (skipping already-indexed ones) then run burst clustering.
    func indexAndGroupBursts() async {
        await similarityModel.indexFiles(files)
        guard !Task.isCancelled else { return }
        let sorted = files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        await similarityModel.groupBursts(files: sorted)
    }

    // MARK: - Re-clustering on threshold change

    /// Re-run burst clustering with the current sensitivity threshold.
    /// Requires embeddings to already be computed — no-ops otherwise.
    func reGroupBursts() async {
        guard !similarityModel.embeddings.isEmpty else { return }
        let sorted = files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        guard !Task.isCancelled else { return }
        await similarityModel.groupBursts(files: sorted)
    }

    // MARK: - Keep Best

    /// Rate the sharpest frame in `groupFiles` at ★★★ and reject all others.
    /// Falls back to the first frame when no sharpness scores are available.
    func keepBestInGroup(from groupFiles: [FileItem]) {
        guard !groupFiles.isEmpty else { return }
        let best = Self.sharpestFile(in: groupFiles, scores: sharpnessModel.scores) ?? groupFiles[0]
        let others = groupFiles.filter { $0.id != best.id }
        updateRating(for: best, rating: 3)
        if !others.isEmpty {
            updateRating(for: others, rating: -1)
        }
    }

    // MARK: - Shared pure helpers

    /// Pick the frame with the highest sharpness score. Returns nil only when
    /// `files` is empty. Kept nonisolated so it can be reused from view-level
    /// cache rebuilds without bouncing to MainActor.
    nonisolated static func sharpestFile(
        in files: [FileItem],
        scores: [UUID: Float],
    ) -> FileItem? {
        files.max(by: { (scores[$0.id] ?? 0) < (scores[$1.id] ?? 0) })
    }

    /// Compute the precomputed display info for a burst group's "best" frame.
    /// Returns nil when scores are empty or the group is empty.
    nonisolated static func bestInGroupInfo(
        files: [FileItem],
        scores: [UUID: Float],
        maxScore: Float,
    ) -> BestInGroupInfo? {
        guard !scores.isEmpty, let best = sharpestFile(in: files, scores: scores) else { return nil }
        let percent: Int? = if let score = scores[best.id], maxScore > 0 {
            Int(min(score / maxScore, 1.0) * 100)
        } else {
            nil
        }
        return BestInGroupInfo(fileName: best.name, percent: percent)
    }
}
