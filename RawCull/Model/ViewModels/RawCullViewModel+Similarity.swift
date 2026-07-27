//
//  RawCullViewModel+Similarity.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    // MARK: - Indexing

    /// Restore reusable artifacts, generate misses, and durably commit each
    /// successful artifact for the current catalog.
    func indexSimilarity() async {
        await similarityModel.hydrateArtifacts(files)
        guard !Task.isCancelled else { return }
        await similarityModel.indexFiles(files)
    }

    // MARK: - Ranking

    /// Rank all indexed images by similarity to the currently selected file.
    /// Reuses saliency labels from the sharpness model for a small subject-mismatch penalty.
    /// Updates filteredFiles ordering via handleSortOrderChange() after ranking.
    func findSimilarToSelected() async {
        guard let anchor = selectedFile else { return }
        await similarityModel.rankSimilar(
            to: anchor.id,
            using: files,
            saliencyInfo: sharpnessModel.saliencyInfo,
        )
        guard !Task.isCancelled else { return }
        await handleSortOrderChange()
    }
}
