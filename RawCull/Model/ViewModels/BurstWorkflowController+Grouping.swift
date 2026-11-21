//
//  BurstWorkflowController+Grouping.swift
//  RawCull
//

import Foundation
import OSLog
import RawCullCore

extension BurstWorkflowController {
    // MARK: - Intelligent burst analysis

    @discardableResult
    func startBurstAnalysis(
        catalog: URL,
        files sorted: [FileItem],
    ) async -> BurstAnalysisPipelineResult? {
        Logger.process.debugMessageOnly("BurstWorkflowController.startBurstAnalysis()")
        let generation = burstAnalysisCoordinator.beginGeneration()
        let request = makeBurstAnalysisPipelineRequest(
            catalog: catalog,
            files: sorted,
            generation: generation,
        )
        let task = Task { [weak self] in
            await self?.runBurstAnalysis(request)
        }
        burstAnalysisCoordinator.register(task, generation: generation)

        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func runBurstAnalysis(
        _ request: BurstAnalysisPipelineRequest,
    ) async -> BurstAnalysisPipelineResult? {
        let catalog = request.catalogIdentity
        let generation = request.generation
        Logger.process.debugMessageOnly(
            "BurstWorkflowController.runBurstAnalysis(): running generation \(generation) for \(request.orderedFiles.count) files",
        )
        let initialReviewStates = burstReviewStates
        let fullCatalogFileIDs = Set(self.catalog.files.map(\.id))
        let result = await burstAnalysisCoordinator.run(
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
                    await self?.weakHostForCallbacks?.applyBurstSharpnessScoringSideEffects(scoredFiles)
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
        await finishBurstAnalysis(generation: generation, applied: result != nil)
        return result
    }

    private func isCurrentBurstAnalysis(generation: Int, catalog: URL) -> Bool {
        burstAnalysisCoordinator.isCurrent(generation: generation)
            && self.catalog.selectedSource?.url == catalog
    }

    private func finishBurstAnalysis(generation: Int) {
        Logger.process.debugMessageOnly(
            "BurstWorkflowController.finishBurstAnalysis(): finishing generation \(generation)",
        )
        burstAnalysisCoordinator.finish(generation: generation)
    }

    /// Finish the run, then apply a sensitivity change the user made while it
    /// was running. Without this the run's start-time threshold would win.
    private func finishBurstAnalysis(generation: Int, applied: Bool) async {
        let shouldRegroup = burstAnalysisCoordinator.takePendingRegroup(generation: generation)
        finishBurstAnalysis(generation: generation)
        guard applied, shouldRegroup, !Task.isCancelled else { return }
        await reGroupBursts()
    }

    /// Refresh similarity artifacts, delete the saved derived burst cache, and
    /// run a fresh analysis pass. Existing valid artifacts remain available if
    /// refreshing an individual file fails.
    func reindexBurstAnalysis() async {
        Logger.process.debugMessageOnly("BurstWorkflowController.reindexBurstAnalysis()")
        guard let catalog = self.catalog.selectedSource?.url, !self.catalog.files.isEmpty else { return }

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
        await similarityFeature.hydrateBurstArtifacts(self.catalog.files)
        guard isCurrentBurstCatalogPreparation(preparationGeneration) else { return }
        await similarityFeature.indexBurstFiles(self.catalog.files, forceRefresh: true)
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
        Logger.process.debugMessageOnly("BurstWorkflowController.prepareForFullCatalogReindex()")
        selection.selectedFileIDs = []
        clearLoadedBurstAnalysisForReindex()
        await host.handleSortOrderChange()
    }

    /// Restore a compatible full-catalog burst snapshot without reaching any
    /// sharpness or similarity computation path.
    @discardableResult
    func restoreExistingFullCatalogBurstAnalysis() async -> Bool {
        Logger.process.debugMessageOnly("BurstWorkflowController.restoreExistingFullCatalogBurstAnalysis()")
        guard let catalog = self.catalog.selectedSource?.url, !self.catalog.files.isEmpty else { return false }
        if hasExistingFullCatalogBurstGroupIndex {
            return true
        }

        let generation = burstAnalysisCoordinator.beginGeneration()
        let sorted = fullCatalogBurstAnalysisFiles
        burstAnalysisCoordinator.updateProgress(
            BurstAnalysisProgress(step: .loadingCache),
        )
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
        else {
            // Nothing was restored, but a regroup requested meanwhile still applies.
            await finishBurstAnalysis(generation: generation, applied: true)
            return false
        }

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
        await finishBurstAnalysis(generation: generation, applied: true)
        return true
    }

    var fullCatalogBurstAnalysisFiles: [FileItem] {
        catalog.files.sorted {
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
        Logger.process.debugMessageOnly("BurstWorkflowController.reGroupBursts()")
        // An active run groups with the threshold it captured at start and
        // would overwrite this regroup; replay it when the run finishes.
        if burstAnalysisProgress.isRunning {
            burstAnalysisCoordinator.hasPendingRegroup = true
            return
        }
        guard !similarityModel.embeddings.isEmpty, let catalog = self.catalog.selectedSource?.url else { return }
        let sorted = completedBurstAnalysisContext
            .flatMap(filesForCompletedBurstAnalysis)
            ?? burstAnalysisTargetFiles
        guard !sorted.isEmpty, !Task.isCancelled else { return }

        let savedStatesBySignature = Dictionary(
            uniqueKeysWithValues: reviewStateSnapshots(catalog: catalog, files: sorted)
                .map { ($0.signature, $0.state) },
        )
        await similarityModel.groupBursts(files: sorted)
        guard !Task.isCancelled, self.catalog.selectedSource?.url == catalog else { return }
        burstReviewSession.restoreReviewStates(restoredBurstReviewStates(
            savedStatesBySignature: savedStatesBySignature,
            groups: similarityModel.burstGroups,
            files: sorted,
            catalog: catalog,
        ))
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

    /// True while burst scoring, indexing, grouping or analysis is running.
    var isDeepAIReviewBlockedByOtherWork: Bool {
        sharpnessModel.isScoring
            || similarityModel.isIndexing
            || similarityModel.isGrouping
            || burstAnalysisProgress.isRunning
    }

    /// Rate the recommended frame in `groupFiles` at ★★★ and reject all others.
    func keepBestInGroup(from groupFiles: [FileItem]) {
        Logger.process.debugMessageOnly("BurstWorkflowController.keepBestInGroup()")
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
        host.updateRating(for: best, rating: 3)
        if !others.isEmpty {
            host.updateRating(for: others, rating: -1)
        }
        markDecisionApplied(groupID: groupID)
    }

    /// Rate the recommended frame at ★★★, second best at ★★, and reject others.
    func keepTopTwoInGroup(from groupFiles: [FileItem]) {
        Logger.process.debugMessageOnly("BurstWorkflowController.keepTopTwoInGroup()")
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
            host.updateRating(for: first, rating: 3)
        }
        if rankedIDs.count > 1,
           let second = groupFiles.first(where: { $0.id == rankedIDs[1] }) {
            host.updateRating(for: second, rating: 2)
        }
        let others = groupFiles.filter { !top.contains($0.id) }
        if !others.isEmpty {
            host.updateRating(for: others, rating: -1)
        }
        markDecisionApplied(groupID: groupID)
    }

    func compareBurstGroup(_ groupFiles: [FileItem], startingAt fileID: FileItem.ID? = nil) {
        Logger.process.debugMessageOnly("BurstWorkflowController.compareBurstGroup()")
        guard !groupFiles.isEmpty else { return }
        let groupID = burstReviewQueueFilter == .singleImages ? -1 : groupID(for: groupFiles)
        activateBurstGroup(groupID: groupID, groupFiles: groupFiles, startingAt: fileID)
    }

    @discardableResult
    func advanceToNextBurstGroup(after currentGroupID: Int) -> Bool {
        Logger.process.debugMessageOnly("BurstWorkflowController.advanceToNextBurstGroup()")
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
            uniqueKeysWithValues: host.activeCatalogFiles.map { ($0.id, $0) },
        )
        let groupFiles = nextGroup.fileIDs.compactMap { filesByID[$0] }
        guard groupFiles.count > 1 else { return false }

        let currentGroupFiles = currentGroup.fileIDs.compactMap { filesByID[$0] }
        if !host.hasRating(in: currentGroupFiles) {
            deferBurstGroup(groupID: currentGroupID)
        }

        activateBurstGroup(groupID: nextGroup.id, groupFiles: groupFiles)
        return true
    }

    private func activateBurstGroup(groupID: Int, groupFiles: [FileItem], startingAt fileID: FileItem.ID? = nil) {
        Logger.process.debugMessageOnly("BurstWorkflowController.activateBurstGroup()")
        activeBurstComparisonGroupID = groupID
        let groupFileIDs = Set(groupFiles.map(\.id))
        let savedRankedIDs = burstAnalysisResults[groupID]?.candidates.map(\.fileID)
        let rankedIDs = if let savedRankedIDs, !savedRankedIDs.isEmpty {
            savedRankedIDs.filter(groupFileIDs.contains)
        } else {
            groupFiles.map(\.id)
        }
        selection.comparisonFileIDs = Array(rankedIDs.prefix(4))
        selection.selectedFileID = fileID.flatMap { groupFileIDs.contains($0) ? $0 : nil } ?? selection.comparisonFileIDs.first
        navigation.selectMainViewMode(.comparisonGrid)
    }

    func returnToActiveBurstGroupView() {
        Logger.process.debugMessageOnly("BurstWorkflowController.returnToActiveBurstGroupView()")
        navigation.closeZoomOverlay()
        activeBurstComparisonGroupID = nil
        navigation.mainViewMode = .similarityGrid
        similarityModel.burstModeActive = true
    }

    func undoLastBurstAction() {
        Logger.process.debugMessageOnly("BurstWorkflowController.undoLastBurstAction()")
        guard let entry = lastBurstUndoEntry,
              let selectedSource = catalog.selectedSource
        else { return }
        ratings.cullingModel.applyRatingStates(entry.previousRatingsByFileName, in: selectedSource.url)
        host.refreshCullingDerivedState()
        lastBurstUndoEntry = nil
        burstReviewSession.synchronizeResultReviewStateAfterUndo(groupID: entry.groupID)
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
              context.catalog == catalog.selectedSource?.url
        else { return false }
        return Set(context.orderedFileIDs) == Set(catalog.files.map(\.id))
    }

    var canUseExistingBurstGroupIndexForActiveScope: Bool {
        guard hasExistingBurstGroupIndex,
              let context = completedBurstAnalysisContext,
              context.catalog == catalog.selectedSource?.url
        else { return false }

        let indexedIDs = Set(context.orderedFileIDs)
        let fullCatalogIDs = Set(catalog.files.map(\.id))
        let activeScopeIDs = Set(host.activeCatalogFiles.map(\.id))
        return indexedIDs == fullCatalogIDs || indexedIDs == activeScopeIDs
    }

    func useExistingBurstGroupIndex() {
        Logger.process.debugMessageOnly("BurstWorkflowController.useExistingBurstGroupIndex()")
        burstReviewQueueFilter = .all
        navigation.selectMainViewMode(.similarityGrid)
        similarityModel.burstModeActive = true
    }

    var filteredBurstGroupsForReviewQueue: [BurstGroup] {
        burstReviewSession.filteredGroups(in: burstGroupsInActiveCatalogScope)
    }

    var burstGroupsInActiveCatalogScope: [BurstGroup] {
        guard host.hasActiveSemanticSearchSelection else {
            return similarityModel.burstGroups
        }

        let activeIDs = Set(host.activeCatalogFiles.map(\.id))
        return similarityModel.burstGroups.compactMap { group in
            let scopedIDs = group.fileIDs.filter(activeIDs.contains)
            guard !scopedIDs.isEmpty else { return nil }
            return BurstGroup(id: group.id, fileIDs: scopedIDs)
        }
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
        let isActive = burstGroupReviewState(groupID: groupID) == .reviewed
        setBurstReviewState(isActive ? .none : .reviewed, groupID: groupID)
        return !isActive
    }

    func deferBurstGroup(groupID: Int) {
        setBurstReviewState(.deferred, groupID: groupID)
    }

    @discardableResult
    func toggleBurstGroupDeferred(groupID: Int) -> Bool {
        let isActive = burstGroupReviewState(groupID: groupID) == .deferred
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

    /// The combined Single Images review group has no winner or ranking.
    /// Its workflow state is persisted on its constituent singleton groups.
    func burstGroupReviewState(groupID: Int) -> BurstReviewState {
        burstReviewSession.reviewState(groupID: groupID, scopedGroups: burstGroupsInActiveCatalogScope)
    }

    var singleImageReviewFiles: [FileItem] {
        let ids = Set(burstGroupsInActiveCatalogScope.filter { $0.fileIDs.count == 1 }.flatMap(\.fileIDs))
        return host.activeCatalogFiles.filter { ids.contains($0.id) }
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
        let activeFiles = host.activeCatalogFiles
        let targets: [FileItem]
        if !selection.selectedFileIDs.isEmpty {
            targets = activeFiles.filter { selection.selectedFileIDs.contains($0.id) }
        } else if case let .stars(rating) = ratings.ratingFilter {
            let visible = catalog.filteredFiles.isEmpty ? activeFiles : catalog.filteredFiles
            targets = visible.filter { self.ratings.rating(for: $0) == rating }
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
            "BurstWorkflowController.recomputeBurstRankings(): ranking \(similarityModel.burstGroups.count) groups",
        )
        let results = makeBurstRankings(files: files, reviewStates: burstReviewStates)
        burstReviewSession.replaceRankings(Dictionary(uniqueKeysWithValues: results.map { ($0.groupID, $0) }))
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
        guard let selectedSource = catalog.selectedSource,
              let override = ratings.cullingModel.overrideWinner(for: groupFiles, in: selectedSource.url),
              let file = groupFiles.first(where: { $0.name == override.winnerFileName })
        else { return nil }
        return (file, override)
    }

    private func applyManualWinnerOverrides(files: [FileItem]) {
        guard let selectedSource = catalog.selectedSource else { return }
        ratings.cullingModel.pruneStaleBurstOverrides(
            validFileNames: Set(self.catalog.files.map(\.name)),
            in: selectedSource.url,
        )

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        for group in similarityModel.burstGroups {
            let groupFiles = group.fileIDs.compactMap { filesByID[$0] }
            guard let winner = manualOverrideWinner(in: groupFiles)?.file else { continue }
            burstReviewSession.applyManualWinnerOverride(groupID: group.id, winnerID: winner.id)
        }
    }

    private func captureUndo(groupID: Int, files: [FileItem]) {
        lastBurstUndoEntry = BurstUndoEntry(
            groupID: groupID,
            previousRatingsByFileName: Dictionary(uniqueKeysWithValues: files.map { ($0.name, ratings.rating(for: $0)) }),
        )
    }

    private func markDecisionApplied(groupID: Int) {
        if burstReviewSession.markDecisionApplied(groupID: groupID, scopedGroups: burstGroupsInActiveCatalogScope) {
            persistBurstReviewStates()
        }
    }

    private func setBurstReviewState(
        _ state: BurstReviewState,
        groupID: Int,
        persist: Bool = true,
    ) {
        burstReviewSession.setReviewState(state, groupID: groupID, scopedGroups: burstGroupsInActiveCatalogScope)
        if persist {
            persistBurstReviewStates()
        }
    }

    private func persistBurstReviewStates() {
        guard let context = completedBurstAnalysisContext,
              catalog.selectedSource?.url == context.catalog,
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
        burstReviewSession.applyAnalysis(rankings: result.rankings, restoredReviewStates: result.restoredReviewStates)
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
        let fullCatalogIDs = Set(catalog.files.map(\.id))
        let completedAnalysisIsScoped = completedBurstAnalysisContext.map {
            Set($0.orderedFileIDs) != fullCatalogIDs
        } ?? false
        guard burstAnalysisProgress.isRunning || completedAnalysisIsScoped
        else { return }

        burstAnalysisCoordinator.cancel()
        completedBurstAnalysisContext = nil
        burstReviewSession.reset()
        selection.comparisonFileIDs = []
        similarityModel.clearBurstGrouping()
    }

    func cancelAndResetBurstAnalysis() {
        burstAnalysisCoordinator.cancel()
        completedBurstAnalysisContext = nil
        burstReviewSession.reset()
        selection.comparisonFileIDs = []
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
            "BurstWorkflowController.saveBurstAnalysisCache(): preparing a snapshot for \(files.count) files",
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog),
              let context = completedBurstAnalysisContext,
              context.generation == generation,
              context.similaritySignature == currentBurstSimilaritySignature
        else { return }

        guard Set(files.map(\.id)) == Set(self.catalog.files.map(\.id)) else {
            Logger.process.debugMessageOnly(
                "BurstWorkflowController.saveBurstAnalysisCache(): preserving the full-catalog cache "
                    + "instead of replacing it with a scoped snapshot",
            )
            return
        }

        let snapshot = BurstAnalysisSnapshotFactory.cacheSnapshot(
            .init(
                catalog: catalog,
                files: files,
                configuration: configuration,
                fallbackThumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
                sharpnessSignature: sharpnessSignature ?? currentBurstSharpnessSignature,
                similaritySignature: context.similaritySignature,
                embeddings: similarityModel.embeddings,
                sharpnessScores: sharpnessModel.scores,
                saliencyInfo: sharpnessModel.saliencyInfo,
                groups: similarityModel.burstGroups,
                boundaryEvidence: similarityModel.burstBoundaryEvidence,
                results: Array(burstAnalysisResults.values),
                reviewStateSnapshots: reviewStateSnapshots(catalog: catalog, files: files),
            ),
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        await burstAnalysisCoordinator.save(snapshot, catalog: catalog)
        Logger.process.debugMessageOnly(
            "BurstWorkflowController.saveBurstAnalysisCache(): cache save returned",
        )
    }

    func cachedReviewStates(from snapshot: BurstAnalysisCacheSnapshot, files: [FileItem]? = nil) -> [Int: BurstReviewState] {
        guard let catalog = self.catalog.selectedSource?.url else { return [:] }
        return BurstReviewStateMapping.restore(
            snapshots: snapshot.reviewStateSnapshots,
            groups: similarityModel.burstGroups,
            files: files ?? self.catalog.files,
            catalog: catalog,
        )
    }

    func reviewStateSnapshots(catalog: URL, files: [FileItem]) -> [BurstReviewStateSnapshot] {
        BurstReviewStateMapping.snapshots(
            states: burstReviewStates,
            groups: similarityModel.burstGroups,
            files: files,
            catalog: catalog,
        )
    }

    func restoredBurstReviewStates(
        savedStatesBySignature: [BurstGroupSignature: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        BurstReviewStateMapping.restore(
            savedStates: savedStatesBySignature,
            groups: groups,
            files: files,
            catalog: catalog,
        )
    }

    func burstSignature(
        for group: BurstGroup,
        filesByID: [UUID: FileItem],
        catalog: URL?,
    ) -> BurstGroupSignature? {
        BurstReviewStateMapping.signature(for: group, filesByID: filesByID, catalog: catalog)
    }

    private var currentBurstSharpnessSignature: BurstSharpnessSignature {
        sharpnessModel.scoringSignature
    }

    var currentBurstSimilaritySignature: BurstSimilaritySignature {
        BurstAnalysisSnapshotFactory.similaritySignature(
            burstSensitivity: similarityModel.burstSensitivity,
            backendDescriptor: similarityModel.backendDescriptor,
            artifactBackendDescriptors: similarityModel.artifactBackendDescriptors,
        )
    }

    func makeBurstAnalysisPipelineRequest(
        catalog: URL,
        files: [FileItem],
        generation: Int,
    ) -> BurstAnalysisPipelineRequest {
        BurstAnalysisSnapshotFactory.pipelineRequest(
            catalog: catalog,
            files: files,
            generation: generation,
            sharpnessSignature: currentBurstSharpnessSignature,
            similaritySignature: currentBurstSimilaritySignature,
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
        )
    }

    private func makeCompletedBurstAnalysisContext(
        catalog: URL,
        files: [FileItem],
        generation: Int,
        similaritySignature: BurstSimilaritySignature? = nil,
    ) -> CompletedBurstAnalysisContext {
        BurstAnalysisSnapshotFactory.completedContext(
            catalog: catalog,
            files: files,
            generation: generation,
            similaritySignature: similaritySignature ?? currentBurstSimilaritySignature,
        )
    }

    private func filesForCompletedBurstAnalysis(
        _ context: CompletedBurstAnalysisContext,
    ) -> [FileItem]? {
        BurstAnalysisSnapshotFactory.files(for: context, in: catalog.files)
    }
}
