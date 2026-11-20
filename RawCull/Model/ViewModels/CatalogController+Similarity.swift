//
//  CatalogController+Similarity.swift
//  RawCull
//

import Foundation
import OSLog

extension CatalogController {
    // MARK: - Ranking

    /// Rank all indexed images by similarity to the currently selected file.
    /// Reuses saliency labels from the sharpness model for a small subject-mismatch penalty.
    /// Updates filteredFiles ordering via handleSortOrderChange() after ranking.
    func findSimilarToSelected() async {
        Logger.process.debugMessageOnly("CatalogController.findSimilarToSelected()")
        guard let anchor = selectedFile else { return }
        let catalogFiles = catalog.files
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
        Logger.process.debugMessageOnly("CatalogController.refreshSemanticSearchSelection()")
        similarityModel.burstModeActive = false
        if burstWorkflow.activeBurstComparisonGroupID != nil
            || navigation.mainViewMode == .comparisonGrid {
            burstWorkflow.activeBurstComparisonGroupID = nil
            selection.comparisonFileIDs = []
            navigation.selectMainViewMode(.similarityGrid)
        }
        await handleSortOrderChange()
        reconcileThumbnailSelectionWithSemanticSearch()
    }
}

extension CatalogController: RawCullSemanticSearchApplicationTarget {
    func prepareApplicationForNewSemanticSearch() {
        Logger.process.debugMessageOnly("CatalogController.prepareApplicationForNewSemanticSearch()")
        burstWorkflow.discardScopedBurstAnalysisIfNeeded()
        selection.selectedFileIDs = []
        similarityModel.burstModeActive = false
        burstWorkflow.activeBurstComparisonGroupID = nil
    }

    func invalidateScopedBurstAnalysisForSemanticSelectionChange() {
        Logger.process.debugMessageOnly("CatalogController.invalidateScopedBurstAnalysisForSemanticSelectionChange()")
        burstWorkflow.discardScopedBurstAnalysisIfNeeded()
    }

    func applySemanticSearchSelection() async {
        Logger.process.debugMessageOnly("CatalogController.applySemanticSearchSelection()")
        await refreshSemanticSearchSelection()
    }

    func restoreOrdinaryCatalogAfterSemanticSearch() async {
        Logger.process.debugMessageOnly("CatalogController.restoreOrdinaryCatalogAfterSemanticSearch()")
        await handleSortOrderChange()
    }
}

extension CatalogController: RawCullSimilarityApplicationContext {
    var currentSimilarityCatalogSnapshot: RawCullSimilarityCatalogSnapshot {
        RawCullSimilarityCatalogSnapshot(
            files: catalog.files,
            identity: RawCullSimilarityCatalogIdentity(
                catalogURL: catalogLifecycle.activeLoadURL ?? catalog.selectedSource?.url,
                generation: similarityCatalogGeneration,
            ),
        )
    }

    func cancelAndResetBurstAnalysisForSimilarityBackendChange() {
        Logger.process.debugMessageOnly("CatalogController.cancelAndResetBurstAnalysisForSimilarityBackendChange()")
        burstWorkflow.cancelAndResetBurstAnalysis()
    }
}
