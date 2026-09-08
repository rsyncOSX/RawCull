//
//  RawCullViewModel+Similarity.swift
//  RawCull
//

import Foundation
import OSLog

extension RawCullViewModel {
    // MARK: - Ranking

    /// Rank all indexed images by similarity to the currently selected file.
    /// Reuses saliency labels from the sharpness model for a small subject-mismatch penalty.
    /// Updates filteredFiles ordering via handleSortOrderChange() after ranking.
    func findSimilarToSelected() async {
        Logger.process.debugMessageOnly("RawCullViewModel.findSimilarToSelected()")
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

    func refreshSemanticSearchSelection() async {
        Logger.process.debugMessageOnly("RawCullViewModel.refreshSemanticSearchSelection()")
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
        Logger.process.debugMessageOnly("RawCullViewModel.prepareApplicationForNewSemanticSearch()")
        discardScopedBurstAnalysisIfNeeded()
        selectedFileIDs = []
        similarityModel.burstModeActive = false
        activeBurstComparisonGroupID = nil
    }

    func invalidateScopedBurstAnalysisForSemanticSelectionChange() {
        Logger.process.debugMessageOnly("RawCullViewModel.invalidateScopedBurstAnalysisForSemanticSelectionChange()")
        discardScopedBurstAnalysisIfNeeded()
    }

    func applySemanticSearchSelection() async {
        Logger.process.debugMessageOnly("RawCullViewModel.applySemanticSearchSelection()")
        await refreshSemanticSearchSelection()
    }

    func restoreOrdinaryCatalogAfterSemanticSearch() async {
        Logger.process.debugMessageOnly("RawCullViewModel.restoreOrdinaryCatalogAfterSemanticSearch()")
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
        Logger.process.debugMessageOnly("RawCullViewModel.cancelAndResetBurstAnalysisForSimilarityBackendChange()")
        cancelAndResetBurstAnalysis()
    }
}
