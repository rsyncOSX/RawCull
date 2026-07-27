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
        await similarityModel.hydrateSemanticArtifacts(files)
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

    /// Rank the currently admitted catalog using the exact text query and
    /// compatible cached CLIP artifacts. This path never invokes image
    /// indexing or source decoding.
    func searchSemantically(for query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            similarityModel.clearSemanticSearch()
            await handleSortOrderChange()
            return
        }
        let admittedFiles = await semanticSearchAdmissionSnapshot()
        guard !Task.isCancelled else { return }
        await similarityModel.rankSemantically(
            query: query,
            files: admittedFiles,
        )
        guard !Task.isCancelled else { return }
        await handleSortOrderChange()
    }

    /// Expand or collapse the ranked catalog without recomputing CLIP
    /// embeddings or cosine scores.
    func setSemanticSearchShowsAllResults(_ showsAll: Bool) async {
        similarityModel.setSemanticSearchShowsAllResults(showsAll)
        await handleSortOrderChange()
    }

    /// Cancel text ranking and immediately restore the ordinary catalog order.
    func clearSemanticSearch() async {
        similarityModel.clearSemanticSearch()
        await handleSortOrderChange()
    }

    /// Cancel an in-flight text query and restore the ordinary catalog order.
    func cancelSemanticSearch() async {
        similarityModel.cancelSemanticSearch()
        await handleSortOrderChange()
    }
}
