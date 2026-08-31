//
//  RawCullViewModel+BurstGrouping.swift
//  RawCull
//

import Foundation
import OSLog
import RawCullCore

extension RawCullViewModel {
    // MARK: - Intelligent burst analysis

    private func startBurstAnalysis(
        catalog: URL,
        files sorted: [FileItem],
    ) async {
        let generation = burstAnalysisCoordinator.beginGeneration()
        let request = makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: sorted,
            generation: generation,
        )
        let task = Task { [weak self] in
            guard let self else { return }
            _ = await self.runBurstAnalysis(request)
        }
        burstAnalysisCoordinator.register(task, generation: generation)

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.startBurstAnalysis(): burst analysis task returned",
        )
    }

    private func runBurstAnalysis(
        _ request: BurstAnalysisPipelineRequest,
    ) async -> BurstAnalysisPipelineResult? {
        let catalog = request.catalogIdentity
        let generation = request.generation
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): running generation \(generation) for \(request.orderedFiles.count) files",
        )
        defer { finishBurstAnalysis(generation: generation) }
        let initialReviewStates = burstReviewStates
        let fullCatalogFileIDs = Set(files.map(\.id))
        return await burstAnalysisCoordinator.run(
            request: request,
            initialReviewStates: initialReviewStates,
            fullCatalogFileIDs: fullCatalogFileIDs,
            callbacks: BurstAnalysisRunCallbacks(
                isCurrent: { [weak self] in
                    self?.isCurrentBurstAnalysis(
                        generation: generation,
                        catalog: catalog,
                    ) ?? false
                },
                updateProgress: { [weak self] progress in
                    self?.burstAnalysisCoordinator.updateProgress(progress)
                },
                didScoreSharpness: { [weak self] scoredFiles in
                    await self?.applyBurstSharpnessScoringSideEffects(scoredFiles)
                },
                applyResult: { [weak self] result in
                    guard let self,
                          self.isCurrentBurstAnalysis(
                              generation: generation,
                              catalog: catalog,
                          )
                    else { return nil }
                    return self.applyBurstAnalysisPipelineResult(result, request: request)
                },
            ),
        )
    }

    private func isCurrentBurstAnalysis(generation: Int, catalog: URL) -> Bool {
        burstAnalysisCoordinator.isCurrent(generation: generation)
            && selectedSource?.url == catalog
    }

    private func finishBurstAnalysis(generation: Int) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.finishBurstAnalysis(): finishing generation \(generation)",
        )
        burstAnalysisCoordinator.finish(generation: generation)
    }

    /// Refresh similarity artifacts, delete the saved derived burst cache, and
    /// run a fresh analysis pass. Existing valid artifacts remain available if
    /// refreshing an individual file fails.
    func reindexBurstAnalysis() async {
        guard let catalog = selectedSource?.url, !files.isEmpty else { return }

        burstCatalogPreparationGeneration &+= 1
        let preparationGeneration = burstCatalogPreparationGeneration
        isPreparingBurstCatalog = true
        defer {
            if burstCatalogPreparationGeneration == preparationGeneration {
                isPreparingBurstCatalog = false
            }
        }

        await prepareForFullCatalogReindex()
        guard isCurrentBurstCatalogPreparation(preparationGeneration) else { return }
        await burstAnalysisCoordinator.deleteCache(catalog: catalog)
        await similarityFeature.hydrateBurstArtifacts(files)
        guard isCurrentBurstCatalogPreparation(preparationGeneration) else { return }
        await similarityFeature.indexBurstFiles(files, forceRefresh: true)
        guard isCurrentBurstCatalogPreparation(preparationGeneration) else { return }
        await startBurstAnalysis(
            catalog: catalog,
            files: fullCatalogBurstAnalysisFiles,
        )
    }

    private func isCurrentBurstCatalogPreparation(_ generation: Int) -> Bool {
        !Task.isCancelled
            && burstCatalogPreparationGeneration == generation
            && isPreparingBurstCatalog
    }

    func prepareForFullCatalogReindex() async {
        selectedFileIDs = []
        clearLoadedBurstAnalysisForReindex()
        await handleSortOrderChange()
    }

    /// Restore a compatible full-catalog burst snapshot without reaching any
    /// sharpness or similarity computation path.
    @discardableResult
    func restoreExistingFullCatalogBurstAnalysis() async -> Bool {
        guard let catalog = selectedSource?.url, !files.isEmpty else { return false }
        if hasExistingFullCatalogBurstGroupIndex {
            return true
        }

        let generation = burstAnalysisCoordinator.beginGeneration()
        let sorted = fullCatalogBurstAnalysisFiles
        burstAnalysisCoordinator.updateProgress(
            BurstAnalysisProgress(step: .loadingCache),
        )
        defer { finishBurstAnalysis(generation: generation) }

        let request = makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: sorted,
            generation: generation,
        )
        guard let cachePreparation = await burstAnalysisCoordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { [weak self] in
                self?.isCurrentBurstAnalysis(
                    generation: generation,
                    catalog: catalog,
                ) ?? false
            },
        ),
            let snapshot = cachePreparation.compatibleSnapshot
        else { return false }

        burstAnalysisCoordinator.applyCachedWorkerState(
            snapshot,
            files: sorted,
        )
        let reviewStates = cachePreparation.restoredReviewStates
        let result = BurstAnalysisPipelineResult(
            groups: snapshot.groups,
            rankings: snapshot.results.map { result in
                var updated = result
                updated.reviewState = reviewStates[result.groupID] ?? .none
                return updated
            }.sorted { $0.groupID < $1.groupID },
            restoredReviewStates: reviewStates,
            cacheOutcome: .hit,
            diagnostics: [],
        )
        _ = applyBurstAnalysisPipelineResult(result, request: request)
        return true
    }

    var fullCatalogBurstAnalysisFiles: [FileItem] {
        files.sorted {
            if $0.effectiveCaptureDate == $1.effectiveCaptureDate {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.effectiveCaptureDate < $1.effectiveCaptureDate
        }
    }

    // MARK: - Re-clustering on threshold change

    /// Re-run burst clustering with the current sensitivity threshold.
    /// Requires embeddings to already be computed — no-ops otherwise.
    func reGroupBursts() async {
        guard !similarityModel.embeddings.isEmpty else { return }
        guard let catalog = selectedSource?.url else { return }
        let sorted = completedBurstAnalysisContext
            .flatMap(filesForCompletedBurstAnalysis)
            ?? burstAnalysisTargetFiles
        guard !sorted.isEmpty else { return }
        guard !Task.isCancelled else { return }

        let savedStatesBySignature = Dictionary(
            uniqueKeysWithValues: reviewStateSnapshots(catalog: catalog, files: sorted)
                .map { ($0.signature, $0.state) },
        )
        await similarityModel.groupBursts(files: sorted)
        guard !Task.isCancelled, selectedSource?.url == catalog else { return }
        burstReviewStates = restoredBurstReviewStates(
            savedStatesBySignature: savedStatesBySignature,
            groups: similarityModel.burstGroups,
            files: sorted,
            catalog: catalog,
        )
        recomputeBurstRankings(files: sorted)

        let generation = completedBurstAnalysisContext?.generation ?? burstAnalysisGeneration
        completedBurstAnalysisContext = makeCompletedBurstAnalysisContext(
            catalog: catalog,
            files: sorted,
            generation: generation,
        )
        await saveBurstAnalysisCache(catalog: catalog, files: sorted, generation: generation)
    }

    // MARK: - User actions

    /// Rate the recommended frame in `groupFiles` at ★★★ and reject all others.
    func keepBestInGroup(from groupFiles: [FileItem]) {
        guard !groupFiles.isEmpty else { return }
        let groupID = groupID(for: groupFiles)
        guard canApplyOneClickCulling(groupID: groupID) else { return }
        let best = manualOverrideWinner(in: groupFiles)?.file
            ?? burstAnalysisResults[groupID]?.recommendedFileID
            .flatMap { id in groupFiles.first { $0.id == id } }
            ?? Self.sharpestFile(in: groupFiles, scores: sharpnessModel.scores)
            ?? groupFiles[0]
        let others = groupFiles.filter { $0.id != best.id }
        captureUndo(groupID: groupID, files: groupFiles)
        updateRating(for: best, rating: 3)
        if !others.isEmpty {
            updateRating(for: others, rating: -1)
        }
        markDecisionApplied(groupID: groupID)
    }

    /// Rate the recommended frame at ★★★, second best at ★★, and reject others.
    func keepTopTwoInGroup(from groupFiles: [FileItem]) {
        guard !groupFiles.isEmpty else { return }
        let groupID = groupID(for: groupFiles)
        guard canApplyOneClickCulling(groupID: groupID) else { return }
        let result = burstAnalysisResults[groupID]
        let rankedIDs = result?.candidates.map(\.fileID) ?? groupFiles
            .sorted { (sharpnessModel.scores[$0.id] ?? 0) > (sharpnessModel.scores[$1.id] ?? 0) }
            .map(\.id)
        let top = Set(rankedIDs.prefix(2))
        captureUndo(groupID: groupID, files: groupFiles)
        if let firstID = rankedIDs.first, let first = groupFiles.first(where: { $0.id == firstID }) {
            updateRating(for: first, rating: 3)
        }
        if rankedIDs.count > 1,
           let second = groupFiles.first(where: { $0.id == rankedIDs[1] }) {
            updateRating(for: second, rating: 2)
        }
        let others = groupFiles.filter { !top.contains($0.id) }
        if !others.isEmpty {
            updateRating(for: others, rating: -1)
        }
        markDecisionApplied(groupID: groupID)
    }

    func compareBurstGroup(_ groupFiles: [FileItem]) {
        guard !groupFiles.isEmpty else { return }
        let groupID = groupID(for: groupFiles)
        activateBurstGroup(groupID: groupID, groupFiles: groupFiles)
    }

    @discardableResult
    func advanceToNextBurstGroup(after currentGroupID: Int) -> Bool {
        let scopedGroups = burstGroupsInActiveCatalogScope
        guard let currentIndex = scopedGroups.firstIndex(where: { $0.id == currentGroupID })
        else { return false }

        let currentGroup = scopedGroups[currentIndex]

        let eligibleGroupIDs = Set(
            filteredBurstGroupsForReviewQueue
                .filter { $0.fileIDs.count > 1 }
                .map(\.id),
        )
        guard let nextGroup = scopedGroups
            .dropFirst(currentIndex + 1)
            .first(where: { $0.fileIDs.count > 1 && eligibleGroupIDs.contains($0.id) })
        else { return false }

        let filesByID = Dictionary(
            uniqueKeysWithValues: activeCatalogFiles.map { ($0.id, $0) },
        )
        let groupFiles = nextGroup.fileIDs.compactMap { filesByID[$0] }
        guard groupFiles.count > 1 else { return false }

        let currentGroupFiles = currentGroup.fileIDs.compactMap { filesByID[$0] }
        if !hasRating(in: currentGroupFiles) {
            deferBurstGroup(groupID: currentGroupID)
        }

        activateBurstGroup(groupID: nextGroup.id, groupFiles: groupFiles)
        return true
    }

    private func activateBurstGroup(groupID: Int, groupFiles: [FileItem]) {
        activeBurstComparisonGroupID = groupID
        let groupFileIDs = Set(groupFiles.map(\.id))
        let savedRankedIDs = burstAnalysisResults[groupID]?.candidates.map(\.fileID)
        let rankedIDs = if let savedRankedIDs, !savedRankedIDs.isEmpty {
            savedRankedIDs.filter(groupFileIDs.contains)
        } else {
            groupFiles.map(\.id)
        }
        comparisonFileIDs = Array(rankedIDs.prefix(4))
        selectedFileID = comparisonFileIDs.first
        selectMainViewMode(.comparisonGrid)
    }

    func returnToActiveBurstGroupView() {
        closeZoomOverlay()
        activeBurstComparisonGroupID = nil
        mainViewMode = .similarityGrid
        similarityModel.burstModeActive = true
    }

    func undoLastBurstAction() {
        guard let entry = lastBurstUndoEntry,
              let selectedSource
        else { return }
        cullingModel.applyRatingStates(entry.previousRatingsByFileName, in: selectedSource.url)
        refreshCullingDerivedState()
        lastBurstUndoEntry = nil
        if var result = burstAnalysisResults[entry.groupID] {
            result.reviewState = burstReviewStates[entry.groupID] ?? .none
            burstAnalysisResults[entry.groupID] = result
        }
    }

    // MARK: - Review queue

    var burstReviewSummary: BurstReviewSummary {
        BurstReviewQueuePolicy.summary(
            for: burstGroupsInActiveCatalogScope,
            resultsByGroupID: burstAnalysisResults,
        )
    }

    var hasCompletedBurstAnalysis: Bool {
        completedBurstAnalysisContext != nil
            && !burstAnalysisProgress.isRunning
            && !similarityModel.isGrouping
    }

    var hasExistingBurstGroupIndex: Bool {
        hasCompletedBurstAnalysis && !similarityModel.burstGroups.isEmpty
    }

    var hasExistingFullCatalogBurstGroupIndex: Bool {
        guard hasExistingBurstGroupIndex,
              let context = completedBurstAnalysisContext,
              context.catalog == selectedSource?.url
        else { return false }
        return Set(context.orderedFileIDs) == Set(files.map(\.id))
    }

    var canUseExistingBurstGroupIndexForActiveScope: Bool {
        guard hasExistingBurstGroupIndex,
              let context = completedBurstAnalysisContext,
              context.catalog == selectedSource?.url
        else { return false }

        let indexedIDs = Set(context.orderedFileIDs)
        let fullCatalogIDs = Set(files.map(\.id))
        let activeScopeIDs = Set(activeCatalogFiles.map(\.id))
        return indexedIDs == fullCatalogIDs || indexedIDs == activeScopeIDs
    }

    func useExistingBurstGroupIndex() {
        burstReviewQueueFilter = .all
        selectMainViewMode(.similarityGrid)
        similarityModel.burstModeActive = true
    }

    var filteredBurstGroupsForReviewQueue: [BurstGroup] {
        let scopedGroups = burstGroupsInActiveCatalogScope
        switch burstReviewQueueFilter {
        case .all:
            return scopedGroups.filter { $0.fileIDs.count > 1 }

        case .singleImages:
            return scopedGroups.filter { $0.fileIDs.count == 1 }

        case .needsReview, .deferred, .markedReviewed, .reviewed:
            break
        }

        return scopedGroups.filter { group in
            guard group.fileIDs.count > 1 else { return false }
            guard let result = burstAnalysisResults[group.id] else {
                return burstReviewQueueFilter == .needsReview
            }
            return BurstReviewQueuePolicy.includes(result, filter: burstReviewQueueFilter)
        }
    }

    var burstGroupsInActiveCatalogScope: [BurstGroup] {
        similarityModel.burstGroups
    }

    // periphery:ignore
    func markBurstGroupNeedsReview(groupID: Int) {
        setBurstReviewState(.needsReview, groupID: groupID)
    }

    func markBurstGroupReviewed(groupID: Int) {
        setBurstReviewState(.reviewed, groupID: groupID)
    }

    @discardableResult
    func toggleBurstGroupReviewed(groupID: Int) -> Bool {
        let isActive = burstAnalysisResults[groupID]?.reviewState == .reviewed
        setBurstReviewState(isActive ? .none : .reviewed, groupID: groupID)
        return !isActive
    }

    func deferBurstGroup(groupID: Int) {
        setBurstReviewState(.deferred, groupID: groupID)
    }

    @discardableResult
    func toggleBurstGroupDeferred(groupID: Int) -> Bool {
        let isActive = burstAnalysisResults[groupID]?.reviewState == .deferred
        setBurstReviewState(isActive ? .none : .deferred, groupID: groupID)
        return !isActive
    }

    // MARK: - Shared pure helpers

    /// Pick the frame with the highest sharpness score. Returns nil only when
    /// `files` is empty. Kept nonisolated so it can be reused from view-level
    /// cache rebuilds without bouncing to MainActor.
    nonisolated static func sharpestFile(
        in files: [FileItem],
        scores: [UUID: Float],
    ) -> FileItem? {
        files.max(by: { (scores[$0.id] ?? 0) < (scores[$1.id] ?? 0) })
    }

    func burstAnalysisResult(for groupID: Int) -> BurstAnalysisResult? {
        burstAnalysisResults[groupID]
    }

    func burstCandidate(for file: FileItem) -> BurstCandidateScore? {
        guard let groupID = similarityModel.burstGroupLookup[file.id] else { return nil }
        return burstAnalysisResults[groupID]?.candidates.first { $0.fileID == file.id }
    }

    var burstAnalysisTargetFiles: [FileItem] {
        burstAnalysisOrderedFiles()
    }

    func burstAnalysisOrderedFiles() -> [FileItem] {
        let activeFiles = activeCatalogFiles
        let targets: [FileItem]
        if !selectedFileIDs.isEmpty {
            targets = activeFiles.filter { selectedFileIDs.contains($0.id) }
        } else if case let .stars(rating) = ratingFilter {
            let visible = filteredFiles.isEmpty ? activeFiles : filteredFiles
            targets = visible.filter { self.rating(for: $0) == rating }
        } else {
            targets = activeFiles
        }

        return targets.sorted { lhs, rhs in
            if lhs.effectiveCaptureDate == rhs.effectiveCaptureDate {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            return lhs.effectiveCaptureDate < rhs.effectiveCaptureDate
        }
    }

    private func recomputeBurstRankings(files: [FileItem]) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.recomputeBurstRankings(): ranking \(similarityModel.burstGroups.count) groups",
        )
        let results = makeBurstRankings(files: files, reviewStates: burstReviewStates)
        burstAnalysisResults = Dictionary(uniqueKeysWithValues: results.map { ($0.groupID, $0) })
        applyManualWinnerOverrides(files: files)
    }

    private func makeBurstRankings(
        files: [FileItem],
        reviewStates: [Int: BurstReviewState],
    ) -> [BurstAnalysisResult] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return BurstRankingEngine.rank(
            groups: similarityModel.burstGroups.filter { $0.fileIDs.count > 1 },
            filesByID: filesByID,
            scores: sharpnessModel.scores,
            maxScore: sharpnessModel.maxScore,
            saliencyInfo: sharpnessModel.saliencyInfo,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            reviewStates: reviewStates,
        )
    }

    private func groupID(for groupFiles: [FileItem]) -> Int {
        groupFiles.lazy.compactMap { self.similarityModel.burstGroupLookup[$0.id] }.first ?? -1
    }

    private func canApplyOneClickCulling(groupID: Int) -> Bool {
        guard let result = burstAnalysisResults[groupID] else { return false }
        return result.canApplyOneClickCulling(hasSharpnessScores: !sharpnessModel.scores.isEmpty)
    }

    func manualOverrideWinner(in groupFiles: [FileItem]) -> (file: FileItem, override: BurstWinnerOverride)? {
        guard let selectedSource,
              let override = cullingModel.overrideWinner(for: groupFiles, in: selectedSource.url),
              let file = groupFiles.first(where: { $0.name == override.winnerFileName })
        else { return nil }
        return (file, override)
    }

    private func applyManualWinnerOverrides(files: [FileItem]) {
        guard let selectedSource else { return }
        cullingModel.pruneStaleBurstOverrides(
            validFileNames: Set(self.files.map(\.name)),
            in: selectedSource.url,
        )

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        for group in similarityModel.burstGroups {
            let groupFiles = group.fileIDs.compactMap { filesByID[$0] }
            guard let winner = manualOverrideWinner(in: groupFiles)?.file else { continue }
            burstReviewStates[group.id] = .manualWinnerOverride
            guard var result = burstAnalysisResults[group.id] else { continue }
            result.recommendedFileID = winner.id
            result.secondBestFileID = result.candidates.first { $0.fileID != winner.id }?.fileID
            result.reviewState = .manualWinnerOverride
            burstAnalysisResults[group.id] = result
        }
    }

    private func captureUndo(groupID: Int, files: [FileItem]) {
        lastBurstUndoEntry = BurstUndoEntry(
            groupID: groupID,
            previousRatingsByFileName: Dictionary(uniqueKeysWithValues: files.map { ($0.name, rating(for: $0)) }),
        )
    }

    private func markDecisionApplied(groupID: Int) {
        if burstAnalysisResults[groupID]?.reviewState == .manualWinnerOverride {
            burstReviewStates[groupID] = .manualWinnerOverride
            return
        }
        setBurstReviewState(.decisionApplied, groupID: groupID, persist: false)
        persistBurstReviewStates()
    }

    private func setBurstReviewState(
        _ state: BurstReviewState,
        groupID: Int,
        persist: Bool = true,
    ) {
        switch state {
        case .none:
            burstReviewStates.removeValue(forKey: groupID)

        default:
            burstReviewStates[groupID] = state
        }
        if var result = burstAnalysisResults[groupID] {
            result.reviewState = state
            burstAnalysisResults[groupID] = result
        }
        if persist {
            persistBurstReviewStates()
        }
    }

    private func persistBurstReviewStates() {
        guard let context = completedBurstAnalysisContext,
              selectedSource?.url == context.catalog,
              burstAnalysisGeneration == context.generation,
              context.similaritySignature == currentBurstSimilaritySignature,
              let contextFiles = filesForCompletedBurstAnalysis(context)
        else { return }

        Task {
            await saveBurstAnalysisCache(
                catalog: context.catalog,
                files: contextFiles,
                generation: context.generation,
            )
        }
    }

    @discardableResult
    private func applyBurstAnalysisPipelineResult(
        _ result: BurstAnalysisPipelineResult,
        request: BurstAnalysisPipelineRequest,
    ) -> BurstAnalysisPipelineResult {
        burstReviewStates = result.restoredReviewStates
        burstAnalysisResults = Dictionary(
            uniqueKeysWithValues: result.rankings.map { ($0.groupID, $0) },
        )
        applyManualWinnerOverrides(files: request.orderedFiles)
        completedBurstAnalysisContext = makeCompletedBurstAnalysisContext(
            catalog: request.catalogIdentity,
            files: request.orderedFiles,
            generation: request.generation,
            similaritySignature: request.similaritySignature,
        )

        return BurstAnalysisPipelineResult(
            groups: result.groups,
            rankings: burstAnalysisResults.values.sorted { $0.groupID < $1.groupID },
            restoredReviewStates: burstReviewStates,
            cacheOutcome: result.cacheOutcome,
            diagnostics: result.diagnostics,
        )
    }

    func clearLoadedBurstAnalysisForReindex() {
        cancelAndResetBurstAnalysis()
    }

    func discardScopedBurstAnalysisIfNeeded() {
        let fullCatalogIDs = Set(files.map(\.id))
        let completedAnalysisIsScoped = completedBurstAnalysisContext.map {
            Set($0.orderedFileIDs) != fullCatalogIDs
        } ?? false
        guard burstAnalysisProgress.isRunning || completedAnalysisIsScoped
        else { return }

        burstAnalysisCoordinator.cancel()
        completedBurstAnalysisContext = nil
        burstAnalysisResults = [:]
        burstReviewStates = [:]
        burstReviewQueueFilter = .all
        activeBurstComparisonGroupID = nil
        lastBurstUndoEntry = nil
        comparisonFileIDs = []
        similarityModel.clearBurstGrouping()
    }

    func cancelAndResetBurstAnalysis() {
        burstAnalysisCoordinator.cancel()
        completedBurstAnalysisContext = nil
        burstAnalysisResults = [:]
        burstReviewStates = [:]
        burstReviewQueueFilter = .all
        activeBurstComparisonGroupID = nil
        lastBurstUndoEntry = nil
        comparisonFileIDs = []
        sharpnessModel.cancelScoring()
        similarityModel.reset()
    }

    private func saveBurstAnalysisCache(
        catalog: URL,
        files: [FileItem],
        generation: Int,
        sharpnessSignature: BurstSharpnessSignature? = nil,
        configuration: BurstAnalysisPipelineConfiguration? = nil,
    ) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.saveBurstAnalysisCache(): preparing a snapshot for \(files.count) files",
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog),
              let context = completedBurstAnalysisContext,
              context.generation == generation,
              context.similaritySignature == currentBurstSimilaritySignature
        else { return }

        guard Set(files.map(\.id)) == Set(self.files.map(\.id)) else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.saveBurstAnalysisCache(): preserving the full-catalog cache "
                    + "instead of replacing it with a scoped snapshot",
            )
            return
        }

        let snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: configuration?.cacheSchemaVersion ?? BurstAnalysisCache.schemaVersion,
            algorithmVersion: configuration?.groupingAlgorithmVersion ?? BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: configuration?.thumbnailMaxPixelSize
                ?? sharpnessModel.effectiveThumbnailMaxPixelSize,
            sharpnessSignature: sharpnessSignature ?? currentBurstSharpnessSignature,
            similaritySignature: context.similaritySignature,
            files: files.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: scoped(similarityModel.embeddings, to: files),
            sharpnessScores: scoped(sharpnessModel.scores, to: files),
            saliencyInfo: scoped(sharpnessModel.saliencyInfo, to: files),
            groups: similarityModel.burstGroups,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            results: Array(burstAnalysisResults.values).sorted { $0.groupID < $1.groupID },
            reviewStateSnapshots: reviewStateSnapshots(catalog: catalog, files: files),
            similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
                files: files,
                artifacts: similarityModel.embeddings,
            ),
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        await burstAnalysisCoordinator.save(snapshot, catalog: catalog)
        Logger.process.debugMessageOnly(
            "RawCullViewModel.saveBurstAnalysisCache(): cache save returned",
        )
    }

    func cachedReviewStates(from snapshot: BurstAnalysisCacheSnapshot, files: [FileItem]? = nil) -> [Int: BurstReviewState] {
        guard let catalog = selectedSource?.url else { return [:] }
        let savedStatesBySignature = Dictionary(
            uniqueKeysWithValues: snapshot.reviewStateSnapshots.map { ($0.signature, $0.state) },
        )
        let filesByID = Dictionary(uniqueKeysWithValues: (files ?? self.files).map { ($0.id, $0) })

        var states: [Int: BurstReviewState] = [:]
        for group in similarityModel.burstGroups {
            guard let signature = burstSignature(for: group, filesByID: filesByID, catalog: catalog),
                  let state = savedStatesBySignature[signature],
                  state != .none
            else { continue }
            states[group.id] = state
        }
        return states
    }

    func reviewStateSnapshots(catalog: URL, files: [FileItem]) -> [BurstReviewStateSnapshot] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return similarityModel.burstGroups.compactMap { group in
            guard let state = burstReviewStates[group.id],
                  state != .none,
                  let signature = burstSignature(for: group, filesByID: filesByID, catalog: catalog)
            else { return nil }
            return BurstReviewStateSnapshot(signature: signature, state: state)
        }
    }

    func restoredBurstReviewStates(
        savedStatesBySignature: [BurstGroupSignature: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            guard let signature = burstSignature(
                for: group,
                filesByID: filesByID,
                catalog: catalog,
            ),
                let state = savedStatesBySignature[signature],
                state != .none
            else { return nil }
            return (group.id, state)
        })
    }

    func burstSignature(
        for group: BurstGroup,
        filesByID: [UUID: FileItem],
        catalog: URL?,
    ) -> BurstGroupSignature? {
        let groupFiles = group.fileIDs.compactMap { filesByID[$0] }
        return BurstGroupSignature(files: groupFiles, catalog: catalog)
    }

    private var currentBurstSharpnessSignature: BurstSharpnessSignature {
        sharpnessModel.scoringSignature
    }

    var currentBurstSimilaritySignature: BurstSimilaritySignature {
        BurstSimilaritySignature(
            groupingConfig: BurstGroupingConfig(
                visualDistanceThreshold: similarityModel.burstSensitivity,
            ),
            backendDescriptor: similarityModel.backendDescriptor,
            artifactBackendDescriptors: similarityModel.artifactBackendDescriptors,
            artifactSchemaVersion: SimilarityScoringModel.artifactSchemaVersion,
            embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
        )
    }

    func makeBurstAnalysisPipelineRequest(
        catalog: URL,
        files: [FileItem],
        generation: Int,
    ) -> BurstAnalysisPipelineRequest {
        let similaritySignature = currentBurstSimilaritySignature
        return BurstAnalysisPipelineRequest(
            catalogIdentity: catalog,
            orderedFiles: files,
            sharpnessSignature: currentBurstSharpnessSignature,
            similaritySignature: similaritySignature,
            generation: generation,
            configuration: BurstAnalysisPipelineConfiguration(
                thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
                grouping: similaritySignature.groupingConfig,
                cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
                groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
            ),
        )
    }

    private func makeCompletedBurstAnalysisContext(
        catalog: URL,
        files: [FileItem],
        generation: Int,
        similaritySignature: BurstSimilaritySignature? = nil,
    ) -> CompletedBurstAnalysisContext {
        CompletedBurstAnalysisContext(
            catalog: catalog,
            orderedFileIDs: files.map(\.id),
            orderedFilePaths: files.map(\.url.path),
            similaritySignature: similaritySignature ?? currentBurstSimilaritySignature,
            generation: generation,
        )
    }

    private func filesForCompletedBurstAnalysis(
        _ context: CompletedBurstAnalysisContext,
    ) -> [FileItem]? {
        let currentByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let currentByPath = Dictionary(uniqueKeysWithValues: files.map { ($0.url.path, $0) })
        var resolved: [FileItem] = []
        resolved.reserveCapacity(context.orderedFileIDs.count)

        for (id, path) in zip(context.orderedFileIDs, context.orderedFilePaths) {
            guard let file = currentByID[id] ?? currentByPath[path] else { return nil }
            resolved.append(file)
        }
        return resolved
    }

    private func scoped<Value>(_ dictionary: [UUID: Value], to files: [FileItem]) -> [UUID: Value] {
        let validIDs = Set(files.map(\.id))
        return dictionary.filter { validIDs.contains($0.key) }
    }
}
