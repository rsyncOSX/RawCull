//
//  RawCullViewModel+Similarity.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    // MARK: - Indexing

    /// Compute Vision feature-print embeddings for all files in the current catalog.
    func indexSimilarity() async {
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
        await handleSortOrderChange()
    }
}
