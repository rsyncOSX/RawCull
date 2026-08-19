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
        let catalogFiles = files
        let catalogFileIDs = Set(catalogFiles.map(\.id))

        if !similarityModel.hasCompleteSimilarityIndex(for: catalogFiles) {
            await similarityModel.indexFiles(catalogFiles)
        }
        guard !Task.isCancelled,
              selectedFile?.id == anchor.id,
              Set(files.map(\.id)) == catalogFileIDs
        else { return }

        await similarityModel.rankSimilar(
            to: anchor.id,
            using: catalogFiles,
            saliencyInfo: sharpnessModel.saliencyInfo,
        )
        guard !Task.isCancelled,
              selectedFile?.id == anchor.id,
              similarityModel.sortBySimilarity,
              Set(files.map(\.id)) == catalogFileIDs
        else { return }
        await handleSortOrderChange()
    }

    /// Rank the currently admitted catalog using the exact text query and
    /// compatible cached CLIP artifacts. This path never invokes image
    /// indexing or source decoding.
    func searchSemantically(for query: String) async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await clearSemanticSearch()
            return
        }
        let admittedFiles = await semanticSearchAdmissionSnapshot()
        guard !Task.isCancelled else { return }
        discardScopedBurstAnalysisIfNeeded()
        selectedFileIDs = []
        similarityModel.burstModeActive = false
        activeBurstComparisonGroupID = nil
        await similarityModel.rankSemantically(
            query: query,
            files: admittedFiles,
        )
        guard !Task.isCancelled else { return }
        await refreshSemanticSearchSelection()
    }

    /// Expand or collapse the ranked catalog without recomputing CLIP
    /// embeddings or cosine scores.
    func setSemanticSearchShowsAllResults(_ showsAll: Bool) async {
        discardScopedBurstAnalysisIfNeeded()
        similarityModel.setSemanticSearchShowsAllResults(showsAll)
        await refreshSemanticSearchSelection()
    }

    /// Adjust the number of highest-ranked images in the shared semantic
    /// working set without recomputing CLIP embeddings or scores.
    func adjustSemanticSearchSelection(by delta: Int) async {
        discardScopedBurstAnalysisIfNeeded()
        similarityModel.adjustSemanticSearchSelection(by: delta)
        await refreshSemanticSearchSelection()
    }

    func setSemanticSearchSelectionCount(_ count: Int) async {
        discardScopedBurstAnalysisIfNeeded()
        similarityModel.setSemanticSearchSelectionCount(count)
        await refreshSemanticSearchSelection()
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

    private func refreshSemanticSearchSelection() async {
        similarityModel.burstModeActive = false
        if activeBurstComparisonGroupID != nil
            || mainViewMode == .comparisonGrid {
            activeBurstComparisonGroupID = nil
            comparisonFileIDs = []
            selectMainViewMode(.similarityGrid)
        }
        await handleSortOrderChange()
        reconcileThumbnailSelectionWithSemanticSearch()
    }
}
