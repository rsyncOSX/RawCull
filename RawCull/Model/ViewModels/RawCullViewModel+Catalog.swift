//
//  RawCullViewModel+Catalog.swift
//  RawCull
//

import Foundation
import OSLog

extension RawCullViewModel {
    func mcpCatalogSummary(scanId: UUID? = nil) -> CatalogSummary? {
        guard let selectedSource, catalogLifecycle.currentSource == selectedSource,
              !scanning, !files.isEmpty
        else { return nil }

        let captureDates = files.lazy.compactMap(\.captureDate)
        let cameras = files.reduce(into: [String: Int]()) { counts, file in
            if let camera = file.exifData?.camera, !camera.isEmpty {
                counts[camera, default: 0] += 1
            }
        }
        return CatalogSummary(
            photoCount: files.count,
            earliestCaptureDate: captureDates.min()?.formatted(.iso8601),
            latestCaptureDate: captureDates.max()?.formatted(.iso8601),
            cameraCounts: cameras,
            snapshotAt: Date().formatted(.iso8601),
            photos: files.map { file in
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
            allowAnalysis: allowAnalysis, catalogId: UUID(), preservingJob: false, recurringFolder: recurringFolder
        )
    }

    @discardableResult
    func authorizeMCPCatalog(
        allowAnalysis: Bool, catalogId: UUID, preservingJob: Bool, recurringFolder: Bool = false
    ) throws -> CatalogGrant {
        guard let source = selectedSource else { throw CocoaError(.fileNoSuchFile) }
        let summary = mcpCatalogSummary()
        let grant = CatalogGrant(
            id: catalogId, displayName: source.name, summary: summary, analysisEnabled: allowAnalysis,
            recurringFolder: allowAnalysis && recurringFolder ? true : nil
        )
        let previous = MCPAnalysisAuthorization.savedData
        if allowAnalysis {
            guard summary != nil, hasActiveSecurityScopedAccess(for: source.url) else {
                throw CocoaError(.fileReadNoPermission)
            }
            let bookmark = try source.url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let authorization = MCPAnalysisAuthorization(
                catalogId: grant.id,
                bookmark: bookmark,
                fingerprint: try MCPAnalysisAuthorization.fingerprint(for: files)
            )
            MCPAnalysisAuthorization.save(try JSONEncoder().encode(authorization))
        }
        do {
            let store = CatalogGrantStore.shared()
            if preservingJob {
                // The setup controller holds the job lock and has checked job ownership.
                try store.writeLocked(grant)
            } else {
                try store.authorize(grant)
            }
        } catch {
            MCPAnalysisAuthorization.save(previous)
            throw error
        }
        if !allowAnalysis { MCPAnalysisAuthorization.save(nil) }
        return grant
    }

    func startCatalogLoad(for source: ARWSourceCatalog?, scopedURL: URL? = nil) {
        Logger.process.debugMessageOnly("RawCullViewModel.startCatalogLoad()")
        if scopedURL == nil, let url = source?.url,
           catalogLifecycle.currentSource == source,
           hasActiveSecurityScopedAccess(for: url) {
            return
        }

        // A view observing the same selection must not replace a queued
        // MCP reload with a transition that lacks its restored bookmark.
        if scopedURL == nil, catalogLifecycle.transitionTask != nil,
           pendingCatalogTransitionSource == source { return }

        let previousSource = catalogLifecycle.currentSource
        pendingCatalogTransitionSource = source
        catalogLifecycle.startTransition(
            flushPersistence: { [weak self] in
                guard let self else { return false }
                return await self.cullingModel.flushPersistence()
            },
            isStillSelected: { [weak self] in self?.selectedSource == source },
            onFailure: { [weak self] in self?.selectedSource = previousSource },
            onReady: { [weak self] in self?.beginCatalogLoad(for: source, scopedURL: scopedURL) },
        )
    }

    private func beginCatalogLoad(for source: ARWSourceCatalog?, scopedURL: URL?) {
        Logger.process.debugMessageOnly("RawCullViewModel.beginCatalogLoad()")
        selectedFileID = nil
        selectedFileIDs = []

        cancelCurrentCatalogLoad()
        similarityCatalogGeneration &+= 1
        catalogLifecycle.currentSource = source
        resetCatalogWorkingSet()
        scanning = source != nil

        guard let url = source?.url else {
            catalogLifecycle.activeLoadURL = nil
            return
        }

        guard startSecurityScopedAccess(for: scopedURL ?? url) else {
            scanning = false
            return
        }

        catalogLifecycle.startLoad(for: url) { [weak self] in
            await self?.handleSourceChange(url: url)
        }
    }

    func cancelCatalogLoad() {
        Logger.process.debugMessageOnly("RawCullViewModel.cancelCatalogLoad()")
        catalogLifecycle.cancelTransition()
        cancelCurrentCatalogLoad()
    }

    private func cancelCurrentCatalogLoad() {
        metadataProgress?.cancel()
        metadataProgress = nil
        thumbnailProgress?.cancel()
        thumbnailProgress = nil
        CombinedReviewLease.shared.invalidate()
        sortGeneration &+= 1
        isSorting = false
        catalogLifecycle.cancelLoad()
        similarityFeature.cancelHydration()
        similarityCatalogGeneration &+= 1
        cancelAndResetBurstAnalysis()

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

        isCreatingThumbnails = false
        scanning = false
    }

    func handleSourceChange(url: URL) async {
        let signposter = OSSignposter(subsystem: "no.blogspot.RawCull", category: "CatalogPerformance")
        let interval = signposter.beginInterval("CatalogOpen", id: signposter.makeSignpostID())
        defer { signposter.endInterval("CatalogOpen", interval) }
        Logger.process.debugMessageOnly("RawCullViewModel.handleSourceChange()")
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        scanning = true
        scanDiscoveredCount = 0

        // Discard sharpness data and filters from the previous catalog
        sharpnessModel.reset()
        similarityFeature.resetCatalogState()
        ratingFilter = .all
        burstReviewQueueFilter = .all

        let metadata = CatalogProgressCoalescer(initial: 0) { [weak self] count in
            guard let self, self.isActiveCatalogLoad(url) else { return }
            self.scanDiscoveredCount = count
        }
        metadataProgress = metadata
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
        metadataProgress = nil

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
            catalogLifecycle.currentSource = nil
            stopActiveSecurityScopedAccess()
            catalogLifecycle.finishLoad(for: url)
            return
        }

        scanning = false
        guard await cullingModel.ensureLoaded(), isActiveCatalogLoad(url), !Task.isCancelled else { return }
        rebuildRatingCache()
        loadPersistedScoringandSaliency()
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: sharpnessModel.scores,
            preloadedSaliency: sharpnessModel.saliencyInfo,
            preloadedAFPointScores: sharpnessModel.afPointScores,
        )

        await prepareCatalogThumbnails(at: url)
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }

        catalogLifecycle.finishLoad(for: url)
    }

    private func prepareCatalogThumbnails(at url: URL) async {
        guard !processedURLs.contains(url) else { return }
        let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        let thumbnailSizePreview = settingsmanager.thumbnailSizePreview

        let progress = CatalogProgressCoalescer(initial: CatalogThumbnailProgress()) { [weak self] value in
            guard let self, self.isActiveCatalogLoad(url) else { return }
            self.fileOperationCompleted = value.completed
            self.fileOperationTotal = value.total
            self.fileOperationEstimatedSeconds = value.estimatedSeconds
        }
        thumbnailProgress = progress
        progress.update(immediately: true) { _ in }
        let handlers = makeCatalogThumbnailHandlers(progress: progress)

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
        // Fire-and-forget per-file callbacks may still be queued. Read the
        // actor's accounting after drain, publish once, then reject late callbacks.
        let counts = await scanAndCreateThumbnails.progressCounts()
        guard isActiveCatalogLoad(url), !Task.isCancelled else { return }
        progress.finish {
            $0.completed = counts.completed
            $0.total = counts.total
            $0.estimatedSeconds = 0
        }
        thumbnailProgress = nil
        processedURLs.insert(url)
        isCreatingThumbnails = false
        currentScanAndCreateThumbnailsActor = nil
    }

    private func makeCatalogThumbnailHandlers(
        progress: CatalogProgressCoalescer<CatalogThumbnailProgress>,
    ) -> FileHandlers {
        CreateFileHandlers().createFileHandlers(
            fileHandler: { [weak self] update in
                guard self?.thumbnailProgress === progress else { return }
                let isTerminal = progress.latest.total > 0 && update >= progress.latest.total
                progress.update(immediately: isTerminal) { $0.completed = max($0.completed, update) }
            },
            maxfilesHandler: { [weak self] maxfiles in
                guard self?.thumbnailProgress === progress else { return }
                progress.update(immediately: true) { $0.total = maxfiles }
            },
            estimatedTimeHandler: { [weak self] seconds in
                guard self?.thumbnailProgress === progress else { return }
                progress.update { $0.estimatedSeconds = seconds }
            },
            memorypressurewarning: { [weak self] warning in
                guard self?.thumbnailProgress === progress else { return }
                self?.setMemoryPressureWarning(warning)
            },
            onExtractionNeeded: { [weak self] in
                guard self?.thumbnailProgress === progress else { return }
                self?.extractionNeeded()
            },
        )
    }

    func handleSortOrderChange() async {
        Logger.process.debugMessageOnly("RawCullViewModel.handleSortOrderChange()")
        sortGeneration &+= 1
        let generation = sortGeneration
        let catalog = currentSimilarityCatalogSnapshot.identity
        let source = selectedSource
        let order = sortOrder
        let text = searchText
        isSorting = true
        defer {
            if sortGeneration == generation {
                isSorting = false
            }
        }
        let sorted = await sortFiles(files, order, text)
        guard !Task.isCancelled, sortGeneration == generation,
              currentSimilarityCatalogSnapshot.identity == catalog,
              selectedSource == source, sortOrder == order, searchText == text else { return }
        catalogDisplayCandidates = sorted
        filteredFiles = applyFilters(to: sorted)
    }

    /// Snapshot the current non-semantic catalog ordering and metadata
    /// admission. Semantic ranking is applied after these filters, so ratings
    /// and filename filtering continue to compose with text search.
    func semanticSearchAdmissionSnapshot() async -> [FileItem] {
        Logger.process.debugMessageOnly("RawCullViewModel.semanticSearchAdmissionSnapshot()")
        let sorted = await ScanFiles.sortFiles(
            files,
            by: sortOrder,
            searchText: searchText,
        )
        return applyNonSemanticFilters(to: sorted)
    }

    /// The active catalog working set. Semantic search turns its selected
    /// highest-ranked results into a durable scope shared by every catalog
    /// workflow until the search is cleared or the catalog is reindexed.
    var activeCatalogFiles: [FileItem] {
        guard semanticSearchFeature.hasResults else { return files }
        let selectedIDs = semanticSearchFeature.selectedFileIDs
        return files.filter { selectedIDs.contains($0.id) }
    }

    var hasActiveSemanticSearchSelection: Bool {
        semanticSearchFeature.hasResults
    }

    // MARK: - Helpers

    func isActiveCatalogLoad(_ url: URL) -> Bool {
        catalogLifecycle.activeLoadURL == url && selectedSource?.url == url
    }

    func preselectFirstVisibleFileByName() {
        Logger.process.debugMessageOnly("RawCullViewModel.preselectFirstVisibleFileByName()")
        selectedFileID = filteredFiles
            .min { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }?
            .id
    }

    func reconcileThumbnailSelectionWithSemanticSearch() {
        guard hasActiveSemanticSearchSelection else { return }

        let visibleIDs = Set(filteredFiles.map(\.id))
        selectedFileIDs.formIntersection(visibleIDs)

        guard let firstVisibleID = filteredFiles.first?.id else {
            selectedFileID = nil
            return
        }
        if selectedFileID.map(visibleIDs.contains) != true {
            selectedFileID = firstVisibleID
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
        if ratingFilter != .all {
            result = result.filter { passesRatingFilter($0) }
        }
        if sharpnessModel.sortBySharpness {
            result = sharpnessModel.sortedByAFPointSharpness(result)
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
