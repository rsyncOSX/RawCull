//
//  RawCullViewModel+Culling.swift
//  RawCull
//

import Foundation

extension RawCullViewModel {
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
        rebuildRatingCache()
        loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            files, preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
            preloadedAFPointScores: sharpnessModel.afPointScores,
        )
        let candidates = catalogDisplayCandidates.isEmpty
            ? sortOrder.sorted(files).filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
            : catalogDisplayCandidates
        filteredFiles = applyFilters(to: candidates)
        let visibleIDs = Set(filteredFiles.map(\.id))
        selection.selectedFileIDs.formIntersection(visibleIDs)
        if selection.selectedFileID.map(visibleIDs.contains) != true {
            selection.selectedFileID = filteredFiles.first?.id
        }
    }

    /// Rebuilds the rating lookup for the selected catalog.
    /// Must be called after any culling store mutation that affects ratings.
    func rebuildRatingCache() {
        ratings.rebuildRatingCache(catalog: selectedSource?.url)
    }

    func extractRatedfilenames(_ rating: Int) -> [String] {
        filteredFiles
            .filter { ratings.getRating(for: $0) >= rating }
            .map(\.name)
    }

    func extractTaggedfilenames() -> [String] {
        ratings.taggedFileNames(catalog: selectedSource?.url, activeNames: Set(activeCatalogFiles.map(\.name)))
    }

    func hasRating(in files: [FileItem]) -> Bool {
        ratings.hasRating(in: files, catalog: selectedSource?.url)
    }

    func updateRating(for file: FileItem, rating: Int) {
        guard let selectedSource else { return }
        ratings.cullingModel.updateRating(fileName: file.name, rating: rating, in: selectedSource.url)
        refreshCullingDerivedState()
    }

    func updateRatingAndAdvance(for file: FileItem, rating: Int, in orderedFiles: [FileItem]) {
        guard selectedSource != nil else { return }
        let nextFileID = orderedFiles
            .firstIndex { $0.id == file.id }
            .flatMap { index -> FileItem.ID? in
                let nextIndex = index + 1
                guard orderedFiles.indices.contains(nextIndex) else { return nil }
                return orderedFiles[nextIndex].id
            }

        updateRating(for: file, rating: rating)

        if let activeBurstComparisonGroupID {
            markBurstGroupReviewed(groupID: activeBurstComparisonGroupID)
        }

        if let nextFileID {
            selection.selectedFileID = nextFileID
        }
    }

    func updateRating(for files: [FileItem], rating: Int) {
        guard let selectedSource else { return }
        ratings.cullingModel.updateRatings(fileNames: files.map(\.name), rating: rating, in: selectedSource.url)
        refreshCullingDerivedState()
    }

    func clearCurrentCatalogCullingState() {
        guard let selectedSource else { return }
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
        rebuildRatingCache()
        guard ratings.ratingFilter != .all else { return }

        let candidates = catalogDisplayCandidates.isEmpty
            ? sortOrder.sorted(files).filter {
                searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
            }
            : catalogDisplayCandidates
        filteredFiles = applyFilters(to: candidates)
    }
}
