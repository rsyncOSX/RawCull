//
//  CatalogController+Loading.swift
//  RawCull
//

import Foundation
import OSLog

extension CatalogController {
    func mcpCatalogSummary(scanId: UUID? = nil) -> CatalogSummary? {
        guard let selectedSource = catalog.selectedSource, catalogLifecycle.currentSource == selectedSource,
              !catalog.scanning, !catalog.files.isEmpty
        else { return nil }

        let captureDates = catalog.files.lazy.compactMap(\.captureDate)
        let cameras = catalog.files.reduce(into: [String: Int]()) { counts, file in
            if let camera = file.exifData?.camera, !camera.isEmpty {
                counts[camera, default: 0] += 1
            }
        }
        return CatalogSummary(
            photoCount: catalog.files.count,
            earliestCaptureDate: captureDates.min()?.formatted(.iso8601),
            latestCaptureDate: captureDates.max()?.formatted(.iso8601),
            cameraCounts: cameras,
            snapshotAt: Date().formatted(.iso8601),
            photos: catalog.files.map { file in
                CatalogPhoto(
                    name: file.url.lastPathComponent,
                    captureDate: file.captureDate?.formatted(.iso8601),
                    camera: file.exifData?.camera,
                )
            },
            scanId: scanId,
        )
    }

    func authorizeMCPCatalog(allowAnalysis: Bool, recurringFolder: Bool) throws -> CatalogGrant {
        try authorizeMCPCatalog(
            allowAnalysis: allowAnalysis, catalogId: UUID(), preservingJob: false,
            recurringFolder: recurringFolder,
        )
    }

    @discardableResult
    func authorizeMCPCatalog(
        allowAnalysis: Bool, catalogId: UUID, preservingJob: Bool, recurringFolder: Bool = false,
    ) throws -> CatalogGrant {
        guard let source = catalog.selectedSource else { throw CocoaError(.fileNoSuchFile) }
        let summary = mcpCatalogSummary()
        let grant = CatalogGrant(
            id: catalogId, displayName: source.name, summary: summary, analysisEnabled: allowAnalysis,
            recurringFolder: allowAnalysis && recurringFolder ? true : nil,
            followUpEnabled: allowAnalysis ? true : nil,
        )
        let previous = MCPAnalysisAuthorization.savedData
        if allowAnalysis {
            guard summary != nil, hasActiveSecurityScopedAccess(for: source.url) else {
                throw CocoaError(.fileReadNoPermission)
            }
            let bookmark = try source.url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil,
            )
            let authorization = try MCPAnalysisAuthorization(
                catalogId: grant.id,
                bookmark: bookmark,
                fingerprint: MCPAnalysisAuthorization.fingerprint(for: catalog.files),
            )
            try MCPAnalysisAuthorization.save(JSONEncoder().encode(authorization))
        }
        do {
            let store = CatalogGrantStore.shared()
            if preservingJob {
                // The setup controller holds the job lock and has checked job ownership.
                try store.writeLocked(grant)
            } else {
                try store.authorize(grant)
                MCPJobPhotoAccess.save(nil)
            }
        } catch {
            MCPAnalysisAuthorization.save(previous)
            throw error
        }
        if !allowAnalysis {
            MCPAnalysisAuthorization.save(nil)
        }
        return grant
    }

    func startCatalogLoad(
        for source: ARWSourceCatalog?, scopedURL: URL? = nil, retainedAccess: RawCullCatalogGrant? = nil,
    ) {
        Logger.process.debugMessageOnly("CatalogController.startCatalogLoad()")
        if scopedURL == nil, let url = source?.url,
           catalogLifecycle.currentSource == source,
           hasActiveSecurityScopedAccess(for: url) {
            return
        }

        // A view observing the same selection must not replace a queued
        // MCP reload with a transition that lacks its restored bookmark.
        if scopedURL == nil, catalogLifecycle.transitionTask != nil,
           catalog.pendingCatalogTransitionSource == source {
            return
        }

        let previousSource = catalogLifecycle.currentSource
        catalog.catalogLoadFailure = nil
        catalog.pendingCatalogTransitionSource = source
        catalogLifecycle.startTransition(
            flushPersistence: { [weak self] in
                guard let self else { return false }
                return await self.ratings.cullingModel.flushPersistence()
            },
            isStillSelected: { [weak self] in self?.catalog.selectedSource == source },
            onFailure: { [weak self] in self?.catalog.selectedSource = previousSource },
            onReady: { [weak self] in
                self?.beginCatalogLoad(for: source, scopedURL: scopedURL, retainedAccess: retainedAccess)
            },
        )
    }

    private func beginCatalogLoad(
        for source: ARWSourceCatalog?, scopedURL: URL?, retainedAccess: RawCullCatalogGrant?,
    ) {
        Logger.process.debugMessageOnly("CatalogController.beginCatalogLoad()")
        selection.selectedFileID = nil
        selection.selectedFileIDs = []

        cancelCurrentCatalogLoad()
        similarityCatalogGeneration &+= 1
        catalogLifecycle.currentSource = source
        resetCatalogWorkingSet()
        catalog.scanning = source != nil

        guard let url = source?.url else {
            catalogLifecycle.activeLoadURL = nil
            return
        }

        if let retainedAccess, retainedAccess.url.path == url.standardizedFileURL.path {
            catalogLifecycle.activateSecurityScopedAccess(retainedAccess)
        } else if !startSecurityScopedAccess(for: scopedURL ?? url) {
            catalog.catalogLoadFailure = .folderAccess
            catalog.scanning = false
            return
        }

        catalogLifecycle.startLoad(for: url) { [weak self] in
            await self?.handleSourceChange(url: url)
        }
    }

    func cancelCatalogLoad() {
        Logger.process.debugMessageOnly("CatalogController.cancelCatalogLoad()")
        catalogLifecycle.cancelTransition()
        cancelCurrentCatalogLoad()
    }

    private func cancelCurrentCatalogLoad() {
        catalog.metadataProgress?.cancel()
        catalog.metadataProgress = nil
        catalog.thumbnailProgress?.cancel()
        catalog.thumbnailProgress = nil
        CombinedReviewLease.shared.invalidate()
        catalog.sortGeneration &+= 1
        catalog.isSorting = false
        catalogLifecycle.cancelLoad()
        similarityFeature.cancelHydration()
        similarityCatalogGeneration &+= 1
        burstWorkflow.cancelAndResetBurstAnalysis()

        catalog.preloadTask?.cancel()
        catalog.preloadTask = nil

        if let actor = catalog.currentScanAndCreateThumbnailsActor {
            Task { await actor.cancelPreload() }
        }
        catalog.currentScanAndCreateThumbnailsActor = nil

        fileOperations.cancelJPGCacheWarming()

        catalog.isCreatingThumbnails = false
        catalog.scanning = false
    }

    func handleSourceChange(url: URL) async {
        let signposter = OSSignposter(subsystem: "no.blogspot.RawCull", category: "CatalogPerformance")
        let interval = signposter.beginInterval("CatalogOpen", id: signposter.makeSignpostID())
        defer { signposter.endInterval("CatalogOpen", interval) }
        Logger.process.debugMessageOnly("CatalogController.handleSourceChange()")
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        catalog.scanning = true
        catalog.scanDiscoveredCount = 0

        // Discard sharpness data and filters from the previous catalog
        sharpnessModel.reset()
        similarityFeature.resetCatalogState()
        ratings.resetForCatalogChange()
        burstWorkflow.burstReviewQueueFilter = .all

        let metadata = CatalogProgressCoalescer(initial: 0) { [weak self] count in
            guard let self, self.isActiveCatalogLoad(url) else { return }
            self.catalog.scanDiscoveredCount = count
        }
        catalog.metadataProgress = metadata
        metadata.update(immediately: true) { $0 = 0 }
        let scan = ScanFiles()
        let scannedFiles = await scan.scanFiles(
            url: url,
            onProgress: { [weak self] count in
                guard let self, self.isActiveCatalogLoad(url) else { return }
                metadata.update { $0 = max($0, count) }
            },
        )
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        metadata.finish()
        catalog.metadataProgress = nil

        // Map raw decoded data → FocusPointsModel here on @MainActor
        if let raw = await scan.decodedFocusPoints {
            guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
            catalog.focusPoints = raw.map {
                FocusPointsModel(sourceFile: $0.sourceFile, focusLocations: [$0.focusLocation])
            }
        } else {
            catalog.focusPoints = nil
        }

        Logger.process.debugMessageOnly("Finished scanning! Total files: \(scannedFiles.count)")

        let sortedFiles = await ScanFiles.sortFiles(
            scannedFiles,
            by: catalog.sortOrder,
            searchText: catalog.searchText,
        )
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }

        catalog.files = scannedFiles
        let hydrationRequest = RawCullSimilarityCatalogHydrationRequest(
            files: scannedFiles,
            catalogIdentity: currentSimilarityCatalogSnapshot.identity,
        )
        guard await similarityFeature.hydrateCatalog(hydrationRequest),
              isActiveCatalogLoad(url), !Task.isCancelled
        else { return }
        catalog.catalogDisplayCandidates = sortedFiles
        catalog.filteredFiles = applyFilters(to: catalog.catalogDisplayCandidates)
        preselectFirstVisibleFileByName()

        guard !catalog.files.isEmpty else {
            let directoryReadFailed = await scan.directoryReadFailed
            guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
            catalog.catalogLoadFailure = directoryReadFailed ? .folderAccess : .noPhotos
            catalog.scanning = false
            catalogLifecycle.currentSource = nil
            stopActiveSecurityScopedAccess()
            catalogLifecycle.finishLoad(for: url)
            return
        }

        catalog.scanning = false
        guard await ratings.cullingModel.ensureLoaded(), isActiveCatalogLoad(url), !Task.isCancelled else { return }
        rebuildRatingCache()
        loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            catalog.files,
            preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
            preloadedAFPointScores: sharpnessModel.afPointScores,
        )

        await prepareCatalogThumbnails(at: url)
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }

        catalogLifecycle.finishLoad(for: url)
    }

    private func prepareCatalogThumbnails(at url: URL) async {
        guard !catalog.processedURLs.contains(url) else { return }
        let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

        let progress = CatalogProgressCoalescer(initial: CatalogThumbnailProgress()) { [weak self] value in
            guard let self, self.isActiveCatalogLoad(url) else { return }
            self.fileOperations.fileOperationCompleted = value.completed
            self.fileOperations.fileOperationTotal = value.total
            self.fileOperations.fileOperationEstimatedSeconds = value.estimatedSeconds
        }
        catalog.thumbnailProgress = progress
        progress.update(immediately: true) { _ in }
        let handlers = makeCatalogThumbnailHandlers(progress: progress)

        let scanAndCreateThumbnails = ScanAndCreateThumbnails()
        await scanAndCreateThumbnails.setFileHandlers(handlers)
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        catalog.currentScanAndCreateThumbnailsActor = scanAndCreateThumbnails

        catalog.preloadTask = Task {
            await scanAndCreateThumbnails.preloadCatalog(
                at: url,
                targetSize: thumbnailSizePreview,
            )
        }

        await catalog.preloadTask?.value
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        // Fire-and-forget per-file callbacks may still be queued. Read the
        // actor's accounting after drain, publish once, then reject late callbacks.
        let counts = await scanAndCreateThumbnails.progressCounts()
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        progress.finish {
            $0.completed = counts.completed
            $0.total = counts.total
            $0.estimatedSeconds = 0
        }
        catalog.thumbnailProgress = nil
        catalog.processedURLs.insert(url)
        catalog.isCreatingThumbnails = false
        catalog.currentScanAndCreateThumbnailsActor = nil
    }

    private func makeCatalogThumbnailHandlers(
        progress: CatalogProgressCoalescer<CatalogThumbnailProgress>,
    ) -> FileHandlers {
        CreateFileHandlers().createFileHandlers(
            fileHandler: { [weak self] update in
                guard self?.catalog.thumbnailProgress === progress else { return }
                let isTerminal = progress.latest.total > 0 && update >= progress.latest.total
                progress.update(immediately: isTerminal) { $0.completed = max($0.completed, update) }
            },
            maxfilesHandler: { [weak self] maxfiles in
                guard self?.catalog.thumbnailProgress === progress else { return }
                progress.update(immediately: true) { $0.total = maxfiles }
            },
            estimatedTimeHandler: { [weak self] seconds in
                guard self?.catalog.thumbnailProgress === progress else { return }
                progress.update { $0.estimatedSeconds = seconds }
            },
            memorypressurewarning: { [weak self] warning in
                guard self?.catalog.thumbnailProgress === progress else { return }
                self?.setMemoryPressureWarning(warning)
            },
            onExtractionNeeded: { [weak self] in
                guard self?.catalog.thumbnailProgress === progress else { return }
                self?.extractionNeeded()
            },
        )
    }

    func handleSortOrderChange() async {
        Logger.process.debugMessageOnly("CatalogController.handleSortOrderChange()")
        catalog.sortGeneration &+= 1
        let generation = catalog.sortGeneration
        let catalog = currentSimilarityCatalogSnapshot.identity
        let source = self.catalog.selectedSource
        let order = self.catalog.sortOrder
        let text = self.catalog.searchText
        self.catalog.isSorting = true
        defer {
            if self.catalog.sortGeneration == generation {
                self.catalog.isSorting = false
            }
        }
        let sorted = await self.catalog.sortFiles(self.catalog.files, order, text)
        guard !Task.isCancelled, self.catalog.sortGeneration == generation,
              currentSimilarityCatalogSnapshot.identity == catalog,
              self.catalog.selectedSource == source, self.catalog.sortOrder == order, self.catalog.searchText == text else { return }
        self.catalog.catalogDisplayCandidates = sorted
        self.catalog.filteredFiles = applyFilters(to: sorted)
    }

    /// Snapshot the current non-semantic catalog ordering and metadata
    /// admission. Semantic ranking is applied after these filters, so ratings
    /// and filename filtering continue to compose with text search.
    func semanticSearchAdmissionSnapshot() async -> [FileItem] {
        Logger.process.debugMessageOnly("CatalogController.semanticSearchAdmissionSnapshot()")
        let sorted = await ScanFiles.sortFiles(
            catalog.files,
            by: catalog.sortOrder,
            searchText: catalog.searchText,
        )
        return applyNonSemanticFilters(to: sorted)
    }

    /// The active catalog working set. Semantic search turns its selected
    /// highest-ranked results into a durable scope shared by every catalog
    /// workflow until the search is cleared or the catalog is reindexed.
    var activeCatalogFiles: [FileItem] {
        guard semanticSearchFeature.hasResults else { return catalog.files }
        let selectedIDs = semanticSearchFeature.selectedFileIDs
        return catalog.files.filter { selectedIDs.contains($0.id) }
    }

    var hasActiveSemanticSearchSelection: Bool {
        semanticSearchFeature.hasResults
    }

    // MARK: - Helpers

    func isActiveCatalogLoad(_ url: URL) -> Bool {
        catalogLifecycle.activeLoadURL == url && catalog.selectedSource?.url == url
    }

    func preselectFirstVisibleFileByName() {
        Logger.process.debugMessageOnly("CatalogController.preselectFirstVisibleFileByName()")
        selection.selectFirstByName(in: catalog.filteredFiles)
    }

    func reconcileThumbnailSelectionWithSemanticSearch() {
        guard hasActiveSemanticSearchSelection else { return }

        let visibleIDs = Set(catalog.filteredFiles.map(\.id))
        selection.selectedFileIDs.formIntersection(visibleIDs)

        guard let firstVisibleID = catalog.filteredFiles.first?.id else {
            selection.selectedFileID = nil
            return
        }
        if selection.selectedFileID.map(visibleIDs.contains) != true {
            selection.selectedFileID = firstVisibleID
        }
    }

    /// Applies the active rating filter and sharpness sort to a pre-sorted file list.
    /// When similarity mode is active, similarity sort runs last and takes precedence
    /// over sharpness sort, with the anchor image always ranked first.
    func applyFilters(to files: [FileItem]) -> [FileItem] {
        var result = applyNonSemanticFilters(to: files)
        if semanticSearchFeature.hasResults {
            let resultOrder = Dictionary(
                uniqueKeysWithValues: semanticSearchFeature.orderedResultIDs
                    .enumerated()
                    .map { ($0.element, $0.offset) },
            )
            result = result.filter { resultOrder[$0.id] != nil }
            result.sort { lhs, rhs in
                let leftOrder = resultOrder[lhs.id] ?? .max
                let rightOrder = resultOrder[rhs.id] ?? .max
                if leftOrder != rightOrder {
                    return leftOrder < rightOrder
                }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return result
        }
        if semanticSearchFeature.hasEmptyIndex {
            return []
        }

        // Image-to-image similarity sort takes precedence over sharpness when
        // semantic search is not active.
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

    private func applyNonSemanticFilters(to files: [FileItem]) -> [FileItem] {
        var result = files
        if ratings.ratingFilter != .all {
            result = result.filter { ratings.passesRatingFilter($0) }
        }
        if sharpnessModel.sortBySharpness {
            result = sharpnessModel.sortedByAFPointSharpness(result)
        }
        return result
    }

    /// Clears every catalog-scoped value together so counts never describe a
    /// source other than `selectedSource` while a transition is in flight.
    private func resetCatalogWorkingSet() {
        catalog.files = []
        catalog.catalogDisplayCandidates = []
        catalog.filteredFiles = []
        catalog.scanDiscoveredCount = 0
        catalog.focusPoints = nil
        ratings.ratingCache = [:]
        ratings.taggedNamesCache = []
    }

    /// Rebuilds the rating lookup for the selected catalog.
    /// Must be called after any culling store mutation that affects ratings.
    func rebuildRatingCache() {
        ratings.rebuildRatingCache(catalog: catalog.selectedSource?.url)
    }

    func extractRatedfilenames(_ rating: Int) -> [String] {
        catalog.filteredFiles
            .filter { ratings.getRating(for: $0) >= rating }
            .map(\.name)
    }

    func extractTaggedfilenames() -> [String] {
        ratings.taggedFileNames(catalog: catalog.selectedSource?.url, activeNames: Set(activeCatalogFiles.map(\.name)))
    }

    func hasRating(in files: [FileItem]) -> Bool {
        ratings.hasRating(in: files, catalog: catalog.selectedSource?.url)
    }
}
