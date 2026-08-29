//
//  RawCullViewModel+Similarity.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
    // MARK: - Ranking

    /// Rank all indexed images by similarity to the currently selected file.
    /// Reuses saliency labels from the sharpness model for a small subject-mismatch penalty.
    /// Updates filteredFiles ordering via handleSortOrderChange() after ranking.
    func findSimilarToSelected() async {
        guard let anchor = selectedFile else { return }
        let catalogFiles = files
        let catalogIdentity = currentSimilarityCatalogSnapshot.identity
        let completion = await similarityFeature.rank(
            RawCullSimilarityRankingRequest(
                anchorFileID: anchor.id,
                files: catalogFiles,
                saliencyInfo: sharpnessModel.saliencyInfo,
                catalogIdentity: catalogIdentity,
            ),
        )
        guard let completion,
              !Task.isCancelled,
              selectedFile?.id == anchor.id,
              similarityFeature.isSimilaritySortingActive,
              currentSimilarityCatalogSnapshot.identity == completion.catalogIdentity
        else { return }
        await handleSortOrderChange()
    }

    /// Rank the currently admitted catalog using the exact text query and
    /// compatible cached CLIP artifacts. This path never invokes image
    /// indexing or source decoding.
    func searchSemantically(for query: String) async {
        await semanticSearchFeature.search(for: query)
    }

    /// Expand or collapse the ranked catalog without recomputing CLIP
    /// embeddings or cosine scores.
    func setSemanticSearchShowsAllResults(_ showsAll: Bool) async {
        await semanticSearchFeature.setShowsAllResults(showsAll)
    }

    /// Adjust the number of highest-ranked images in the shared semantic
    /// working set without recomputing CLIP embeddings or scores.
    func adjustSemanticSearchSelection(by delta: Int) async {
        await semanticSearchFeature.adjustSelection(by: delta)
    }

    /// Cancel text ranking and immediately restore the ordinary catalog order.
    func clearSemanticSearch() async {
        await semanticSearchFeature.clear()
    }

    /// Cancel an in-flight text query and restore the ordinary catalog order.
    func cancelSemanticSearch() async {
        await semanticSearchFeature.cancel()
    }

    func refreshSemanticSearchSelection() async {
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

extension RawCullViewModel: RawCullSemanticSearchApplicationTarget {
    func prepareApplicationForNewSemanticSearch() {
        discardScopedBurstAnalysisIfNeeded()
        selectedFileIDs = []
        similarityModel.burstModeActive = false
        activeBurstComparisonGroupID = nil
    }

    func invalidateScopedBurstAnalysisForSemanticSelectionChange() {
        discardScopedBurstAnalysisIfNeeded()
    }

    func applySemanticSearchSelection() async {
        await refreshSemanticSearchSelection()
    }

    func restoreOrdinaryCatalogAfterSemanticSearch() async {
        await handleSortOrderChange()
    }
}

extension RawCullViewModel: RawCullSimilarityApplicationContext {
    var currentSimilarityCatalogSnapshot: RawCullSimilarityCatalogSnapshot {
        RawCullSimilarityCatalogSnapshot(
            files: files,
            identity: RawCullSimilarityCatalogIdentity(
                catalogURL: activeCatalogLoadURL ?? selectedSource?.url,
                generation: similarityCatalogGeneration,
            ),
        )
    }

    func cancelAndResetBurstAnalysisForSimilarityBackendChange() {
        cancelAndResetBurstAnalysis()
    }
}
