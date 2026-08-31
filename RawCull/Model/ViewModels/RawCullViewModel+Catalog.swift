//
//  RawCullViewModel+Catalog.swift
//  RawCull
//

import OSLog

extension RawCullViewModel {
    func startCatalogLoad(for source: ARWSourceCatalog?) {
        if let url = source?.url,
           currentselectedSource == source,
           hasActiveSecurityScopedAccess(for: url) {
            return
        }

        let previousSource = currentselectedSource
        catalogTransitionTask?.cancel()
        catalogTransitionTask = Task {
            guard await cullingModel.flushPersistence() else {
                if selectedSource == source {
                    selectedSource = previousSource
                }
                return
            }
            guard !Task.isCancelled, selectedSource == source else { return }
            beginCatalogLoad(for: source)
            catalogTransitionTask = nil
        }
    }

    private func beginCatalogLoad(for source: ARWSourceCatalog?) {
        selectedFileID = nil
        selectedFileIDs = []

        cancelCatalogLoad()
        similarityCatalogGeneration &+= 1
        currentselectedSource = source
        resetCatalogWorkingSet()
        scanning = source != nil

        guard let url = source?.url else {
            activeCatalogLoadURL = nil
            return
        }

        guard startSecurityScopedAccess(for: url) else {
            scanning = false
            return
        }

        activeCatalogLoadURL = url
        catalogLoadTask = Task(priority: .background) {
            await self.handleSourceChange(url: url)
        }
    }

    func cancelCatalogLoad() {
        catalogLoadTask?.cancel()
        catalogLoadTask = nil
        similarityFeature.cancelHydration()
        similarityCatalogGeneration &+= 1
        activeCatalogLoadURL = nil
        currentselectedSource = nil
        cancelAndResetBurstAnalysis()
        stopActiveSecurityScopedAccess()

        preloadTask?.cancel()
        preloadTask = nil

        jpgCacheWarmTask?.cancel()
        jpgCacheWarmTask = nil

        if let actor = currentScanAndCreateThumbnailsActor {
            Task { await actor.cancelPreload() }
        }
        currentScanAndCreateThumbnailsActor = nil

        if let actor = currentScanAndExtractJPGsActor {
            Task { await actor.cancelExtraction() }
        }
        currentScanAndExtractJPGsActor = nil

        creatingthumbnails = false
        scanning = false
    }

    func handleSourceChange(url: URL) async {
        guard isActiveCatalogLoad(url) else { return }
        scanning = true
        scanDiscoveredCount = 0

        // Discard sharpness data and filters from the previous catalog
        sharpnessModel.reset()
        similarityFeature.resetCatalogState()
        ratingFilter = .all
        burstReviewQueueFilter = .all

        let scan = ScanFiles()
        let scannedFiles = await scan.scanFiles(
            url: url,
            onProgress: { [weak self] count in
                guard let self, self.isActiveCatalogLoad(url) else { return }
                self.scanDiscoveredCount = count
            },
        )
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }

        // Map raw decoded data → FocusPointsModel here on @MainActor
        if let raw = await scan.decodedFocusPoints {
            guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
            focusPoints = raw.map {
                FocusPointsModel(sourceFile: $0.sourceFile, focusLocations: [$0.focusLocation])
            }
        } else {
            focusPoints = nil
        }

        Logger.process.debugMessageOnly("Finished scanning! Total files: \(scannedFiles.count)")

        let sortedFiles = await ScanFiles.sortFiles(
            scannedFiles,
            by: sortOrder,
            searchText: searchText,
        )
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }

        files = scannedFiles
        let hydrationRequest = RawCullSimilarityCatalogHydrationRequest(
            files: scannedFiles,
            catalogIdentity: currentSimilarityCatalogSnapshot.identity,
        )
        guard await similarityFeature.hydrateCatalog(hydrationRequest),
              isActiveCatalogLoad(url), !Task.isCancelled
        else { return }
        catalogDisplayCandidates = sortedFiles
        filteredFiles = applyFilters(to: catalogDisplayCandidates)
        preselectFirstVisibleFileByName()

        guard !files.isEmpty else {
            scanning = false
            currentselectedSource = nil
            stopActiveSecurityScopedAccess()
            if activeCatalogLoadURL == url {
                catalogLoadTask = nil
                activeCatalogLoadURL = nil
            }
            return
        }

        scanning = false
        guard cullingModel.loadSavedFiles() else { return }
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        rebuildRatingCache()
        loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
        )

        if !processedURLs.contains(url) {
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: { [weak self] update in
                    guard let self, self.isActiveCatalogLoad(url) else { return }
                    self.fileHandler(update)
                },
                maxfilesHandler: { [weak self] maxfiles in
                    guard let self, self.isActiveCatalogLoad(url) else { return }
                    self.maxfilesHandler(maxfiles)
                },
                estimatedTimeHandler: { [weak self] seconds in
                    guard let self, self.isActiveCatalogLoad(url) else { return }
                    self.estimatedTimeHandler(seconds)
                },
                memorypressurewarning: { [weak self] warning in
                    guard let self, self.isActiveCatalogLoad(url) else { return }
                    self.setMemoryPressureWarning(warning)
                },
                onExtractionNeeded: { [weak self] in
                    guard let self, self.isActiveCatalogLoad(url) else { return }
                    self.extractionNeeded()
                },
            )

            let scanAndCreateThumbnails = ScanAndCreateThumbnails()
            await scanAndCreateThumbnails.setFileHandlers(handlers)
            guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
            currentScanAndCreateThumbnailsActor = scanAndCreateThumbnails

            preloadTask = Task {
                await scanAndCreateThumbnails.preloadCatalog(
                    at: url,
                    targetSize: thumbnailSizePreview,
                )
            }

            await preloadTask?.value
            guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
            processedURLs.insert(url)
            creatingthumbnails = false
            currentScanAndCreateThumbnailsActor = nil
        }

        if activeCatalogLoadURL == url {
            catalogLoadTask = nil
            activeCatalogLoadURL = nil
        }
    }

    func handleSortOrderChange() async {
        issorting = true
        let sorted = await ScanFiles.sortFiles(files, by: sortOrder, searchText: searchText)
        catalogDisplayCandidates = sorted
        filteredFiles = applyFilters(to: catalogDisplayCandidates)
        issorting = false
    }

    var activeCatalogFiles: [FileItem] {
        files
    }

    // MARK: - Helpers

    func isActiveCatalogLoad(_ url: URL) -> Bool {
        activeCatalogLoadURL == url && selectedSource?.url == url
    }

    func preselectFirstVisibleFileByName() {
        selectedFileID = filteredFiles
            .min { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }?
            .id
    }

    /// Applies the active rating filter and sharpness sort to a pre-sorted file list.
    /// When similarity mode is active, similarity sort runs last and takes precedence
    /// over sharpness sort, with the anchor image always ranked first.
    func applyFilters(to files: [FileItem]) -> [FileItem] {
        var result = applyCatalogFilters(to: files)

        // Image-to-image similarity sort takes precedence over sharpness when
        // image similarity is active.
        if similarityModel.sortBySimilarity, !similarityModel.distances.isEmpty {
            let distances = similarityModel.distances
            let anchorID = similarityModel.anchorFileID
            result.sort { lhs, rhs in
                // Anchor image always sorts first; use stable tie-breaking by name.
                if lhs.id == anchorID {
                    return true
                }
                if rhs.id == anchorID {
                    return false
                }
                let dl = distances[lhs.id] ?? .greatestFiniteMagnitude
                let dr = distances[rhs.id] ?? .greatestFiniteMagnitude
                if dl != dr {
                    return dl < dr
                }
                return lhs.name < rhs.name
            }
        }
        return result
    }

    private func applyCatalogFilters(to files: [FileItem]) -> [FileItem] {
        var result = files
        if ratingFilter != .all {
            result = result.filter { passesRatingFilter($0) }
        }
        if sharpnessModel.sortBySharpness, !sharpnessModel.scores.isEmpty {
            let scores = sharpnessModel.scores
            result.sort { (scores[$0.id] ?? -1) > (scores[$1.id] ?? -1) }
        }
        return result
    }

    /// Clears every catalog-scoped value together so counts never describe a
    /// source other than `selectedSource` while a transition is in flight.
    private func resetCatalogWorkingSet() {
        files = []
        catalogDisplayCandidates = []
        filteredFiles = []
        scanDiscoveredCount = 0
        focusPoints = nil
        ratingCache = [:]
        taggedNamesCache = []
    }
}
