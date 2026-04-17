//
//  RawCullViewModel+Catalog.swift
//  RawCull
//

import OSLog

extension RawCullViewModel {
    func handleSourceChange(url: URL) async {
        scanning = true

        // Discard sharpness data and filters from the previous catalog
        sharpnessModel.reset()
        similarityModel.reset()
        ratingFilter = .all

        let scan = ScanFiles()

        files = await scan.scanFiles(
            url: url,
            onProgress: countingScannedFiles,
        )

        // Map raw decoded data → FocusPointsModel here on @MainActor
        if let raw = await scan.decodedFocusPoints {
            focusPoints = raw.map {
                FocusPointsModel(sourceFile: $0.sourceFile, focusLocations: [$0.focusLocation])
            }
        } else {
            focusPoints = nil
        }

        Logger.process.debugMessageOnly("Finished scanning! Total files: \(files.count)")

        filteredFiles = await applyFilters(to: ScanFiles.sortFiles(
            files,
            by: sortOrder,
            searchText: searchText,
        ))

        guard !files.isEmpty else {
            scanning = false
            return
        }

        scanning = false
        cullingModel.loadSavedFiles()
        rebuildRatingCache()
        loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
        )

        if !processedURLs.contains(url) {
            processedURLs.insert(url)
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: fileHandler,
                maxfilesHandler: maxfilesHandler,
                estimatedTimeHandler: estimatedTimeHandler,
                memorypressurewarning: memorypressurewarning,
                onExtractionNeeded: extractionNeeded,
            )

            let scanAndCreateThumbnails = ScanAndCreateThumbnails()
            await scanAndCreateThumbnails.setFileHandlers(handlers)
            currentScanAndCreateThumbnailsActor = scanAndCreateThumbnails

            preloadTask = Task {
                await scanAndCreateThumbnails.preloadCatalog(
                    at: url,
                    targetSize: thumbnailSizePreview,
                )
            }

            await preloadTask?.value
            creatingthumbnails = false
            currentScanAndCreateThumbnailsActor = nil
        }
    }

    func handleSortOrderChange() async {
        issorting = true
        var sorted = await ScanFiles.sortFiles(files, by: sortOrder, searchText: searchText)
        sorted = applyFilters(to: sorted)
        filteredFiles = sorted
        issorting = false
    }

    func handleSearchTextChange() async {
        issorting = true
        var sorted = await ScanFiles.sortFiles(files, by: sortOrder, searchText: searchText)
        sorted = applyFilters(to: sorted)
        filteredFiles = sorted
        issorting = false
    }

    // MARK: - Helpers

    /// Applies the active rating filter, aperture filter, and sharpness sort to a pre-sorted
    /// file list. When similarity mode is active, similarity sort runs last and takes precedence
    /// over sharpness sort, with the anchor image always ranked first.
    private func applyFilters(to files: [FileItem]) -> [FileItem] {
        var result = files
        if ratingFilter != .all {
            result = result.filter { passesRatingFilter($0) }
        }
        if sharpnessModel.apertureFilter != .all {
            let filter = sharpnessModel.apertureFilter
            result = result.filter { filter.matches($0) }
        }
        if sharpnessModel.sortBySharpness, !sharpnessModel.scores.isEmpty {
            let scores = sharpnessModel.scores
            result.sort { (scores[$0.id] ?? -1) > (scores[$1.id] ?? -1) }
        }
        if let label = sharpnessModel.saliencyCategoryFilter {
            let info = sharpnessModel.saliencyInfo
            result = result.filter { info[$0.id]?.subjectLabel == label }
        }
        // Similarity sort takes precedence over sharpness sort when active.
        if similarityModel.sortBySimilarity, !similarityModel.distances.isEmpty {
            let distances = similarityModel.distances
            let anchorID = similarityModel.anchorFileID
            result.sort { lhs, rhs in
                // Anchor image always sorts first; use stable tie-breaking by name.
                if lhs.id == anchorID { return true }
                if rhs.id == anchorID { return false }
                let dl = distances[lhs.id] ?? .greatestFiniteMagnitude
                let dr = distances[rhs.id] ?? .greatestFiniteMagnitude
                if dl != dr { return dl < dr }
                return lhs.name < rhs.name
            }
        }
        return result
    }
}
