//
//  CullingController+Ratings.swift
//  RawCull
//

import Foundation

extension CullingController {
    @discardableResult
    func retryCullingPersistence() async -> Bool {
        let wasLoadingStore = ratings.cullingModel.loadState != .ready
        let succeeded = await ratings.cullingModel.retryPersistence()
        if succeeded, wasLoadingStore {
            restoreCullingPresentation()
        }
        return succeeded
    }

    @discardableResult
    func archiveCullingStoreAndReset() async -> Bool {
        let succeeded = await ratings.cullingModel.archiveCorruptStoreAndReset()
        // Reset changes memory even if the subsequent disk write fails.
        if ratings.cullingModel.loadState == .ready {
            restoreCullingPresentation()
        }
        return succeeded
    }

    private func restoreCullingPresentation() {
        sharpnessModel.reset()
        catalogController.rebuildRatingCache()
        catalogController.loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            catalog.files, preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
            preloadedAFPointScores: sharpnessModel.afPointScores,
        )
        let candidates = catalog.catalogDisplayCandidates.isEmpty
            ? catalog.sortOrder.sorted(catalog.files).filter { catalog.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(catalog.searchText) }
            : catalog.catalogDisplayCandidates
        catalog.filteredFiles = catalogController.applyFilters(to: candidates)
        let visibleIDs = Set(catalog.filteredFiles.map(\.id))
        selection.selectedFileIDs.formIntersection(visibleIDs)
        if selection.selectedFileID.map(visibleIDs.contains) != true {
            selection.selectedFileID = catalog.filteredFiles.first?.id
        }
    }

    func updateRating(for file: FileItem, rating: Int) {
        guard let selectedSource = catalog.selectedSource else { return }
        ratings.cullingModel.updateRating(fileName: file.name, rating: rating, in: selectedSource.url)
        refreshCullingDerivedState()
    }

    func updateRatingAndAdvance(for file: FileItem, rating: Int, in orderedFiles: [FileItem]) {
        guard catalog.selectedSource != nil else { return }
        let nextFileID = orderedFiles
            .firstIndex { $0.id == file.id }
            .flatMap { index -> FileItem.ID? in
                let nextIndex = index + 1
                guard orderedFiles.indices.contains(nextIndex) else { return nil }
                return orderedFiles[nextIndex].id
            }

        updateRating(for: file, rating: rating)

        if let activeBurstComparisonGroupID = burstWorkflow.activeBurstComparisonGroupID {
            burstWorkflow.markBurstGroupReviewed(groupID: activeBurstComparisonGroupID)
        }

        if let nextFileID {
            selection.selectedFileID = nextFileID
        }
    }

    func updateRating(for files: [FileItem], rating: Int) {
        guard let selectedSource = catalog.selectedSource else { return }
        ratings.cullingModel.updateRatings(fileNames: files.map(\.name), rating: rating, in: selectedSource.url)
        refreshCullingDerivedState()
    }

    func clearCurrentCatalogCullingState() {
        guard let selectedSource = catalog.selectedSource else { return }
        ratings.cullingModel.resetSavedFiles(in: selectedSource.url)
        sharpnessModel.reset()
        similarityFeature.resetCatalogState()
        refreshCullingDerivedState()
    }

    func clearAllCullingState() {
        ratings.cullingModel.resetAllSavedFiles()
        sharpnessModel.reset()
        similarityFeature.resetCatalogState()
        refreshCullingDerivedState()
    }

    /// Synchronizes the cached rating lookup and the displayed catalog
    /// projection after every persisted culling mutation.
    func refreshCullingDerivedState() {
        catalogController.rebuildRatingCache()
        guard ratings.ratingFilter != .all else { return }

        let candidates = catalog.catalogDisplayCandidates.isEmpty
            ? catalog.sortOrder.sorted(catalog.files).filter {
                catalog.searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(catalog.searchText)
            }
            : catalog.catalogDisplayCandidates
        catalog.filteredFiles = catalogController.applyFilters(to: candidates)
    }
}
