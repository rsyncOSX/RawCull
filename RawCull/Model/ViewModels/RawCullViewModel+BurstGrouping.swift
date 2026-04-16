//
//  RawCullViewModel+BurstGrouping.swift
//  RawCull
//

import Foundation

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
        await similarityModel.groupBursts(files: sorted)
    }

    // MARK: - Keep Best

    /// Rate the sharpest frame in `groupFiles` at ★★★ and reject all others.
    /// Falls back to the first frame when no sharpness scores are available.
    func keepBestInGroup(from groupFiles: [FileItem]) {
        guard !groupFiles.isEmpty else { return }
        let scores = sharpnessModel.scores
        let best = groupFiles.max(by: {
            (scores[$0.id] ?? 0) < (scores[$1.id] ?? 0)
        }) ?? groupFiles[0]
        let others = groupFiles.filter { $0.id != best.id }
        updateRating(for: best, rating: 3)
        if !others.isEmpty {
            updateRating(for: others, rating: -1)
        }
    }
}
