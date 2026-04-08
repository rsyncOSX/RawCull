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

        if !processedURLs.contains(url) {
            processedURLs.insert(url)
            creatingthumbnails = true

            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: fileHandler,
                maxfilesHandler: maxfilesHandler,
                estimatedTimeHandler: estimatedTimeHandler,
                memorypressurewarning: memorypressurewarning,
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

    /// Applies the active rating filter, aperture filter, and sharpness sort to a pre-sorted file list.
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
        return result
    }
}
