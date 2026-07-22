//
//  RawCullViewModel+BurstGrouping.swift
//  RawCull
//

import Foundation
import OSLog
import PhotoAIContracts
import RawCullCore

extension RawCullViewModel {
    // MARK: - Intelligent burst analysis

    /// Run the full intelligent burst analysis pipeline: load cache when valid,
    /// score sharpness, index similarity, group bursts, rank candidates, and
    /// persist the analysis artifacts.
    func analyzeBursts() async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.analyzeBursts(): starting burst analysis",
        )
        guard let catalog = selectedSource?.url, !files.isEmpty else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.analyzeBursts(): skipped because the catalog or files are unavailable",
            )
            return
        }
        let sorted = burstAnalysisTargetFiles
        guard !sorted.isEmpty else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.analyzeBursts(): skipped because no files match the active analysis scope",
            )
            return
        }

        burstAnalysisTask?.cancel()
        burstAnalysisGeneration &+= 1
        let generation = burstAnalysisGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runBurstAnalysis(
                catalog: catalog,
                files: sorted,
                generation: generation,
            )
        }
        burstAnalysisTask = task

        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.analyzeBursts(): burst analysis task returned",
        )
    }

    private func runBurstAnalysis(
        catalog: URL,
        files sorted: [FileItem],
        generation: Int,
    ) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): running generation \(generation) for \(sorted.count) files",
        )
        defer { finishBurstAnalysis(generation: generation) }
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }

        burstAnalysisProgress = BurstAnalysisProgress(step: .loadingCache)
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): loading burst analysis cache",
        )
        if let snapshot = await burstAnalysisCacheLoad(
            catalog,
            sorted,
            sharpnessModel.effectiveThumbnailMaxPixelSize,
            currentBurstSharpnessSignature,
            currentBurstSimilaritySignature,
        ) {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.runBurstAnalysis(): cache hit; applying cached analysis",
            )
            guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
            applyCachedBurstAnalysis(
                remapCachedSnapshot(snapshot, to: sorted),
                catalog: catalog,
                files: sorted,
                generation: generation,
            )
            return
        }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): cache miss; running analysis pipeline",
        )

        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        if sorted.contains(where: { sharpnessModel.scores[$0.id] == nil }) {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.runBurstAnalysis(): scoring missing sharpness results",
            )
            burstAnalysisProgress = BurstAnalysisProgress(
                step: .scoringSharpness,
                total: sorted.count,
            )
            await calibrateAndScoreBurstFiles(sorted)
        } else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.runBurstAnalysis(): reusing existing sharpness results",
            )
        }

        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        if sorted.contains(where: { similarityModel.embeddings[$0.id] == nil }) {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.runBurstAnalysis(): indexing missing similarity artifacts",
            )
            burstAnalysisProgress = BurstAnalysisProgress(
                step: .indexingSimilarity,
                total: sorted.count,
            )
            await similarityModel.indexFiles(sorted)
        } else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.runBurstAnalysis(): reusing existing similarity artifacts",
            )
        }

        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): grouping bursts",
        )
        burstAnalysisProgress = BurstAnalysisProgress(step: .grouping)
        await similarityModel.groupBursts(files: sorted)

        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): ranking burst candidates",
        )
        burstAnalysisProgress = BurstAnalysisProgress(step: .ranking)
        recomputeBurstRankings(files: sorted)
        completedBurstAnalysisContext = makeCompletedBurstAnalysisContext(
            catalog: catalog,
            files: sorted,
            generation: generation,
        )

        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        Logger.process.debugMessageOnly(
            "RawCullViewModel.runBurstAnalysis(): saving burst analysis cache",
        )
        burstAnalysisProgress = BurstAnalysisProgress(step: .savingCache)
        await saveBurstAnalysisCache(catalog: catalog, files: sorted, generation: generation)
    }

    private func isCurrentBurstAnalysis(generation: Int, catalog: URL) -> Bool {
        !Task.isCancelled
            && burstAnalysisGeneration == generation
            && selectedSource?.url == catalog
    }

    private func finishBurstAnalysis(generation: Int) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.finishBurstAnalysis(): finishing generation \(generation)",
        )
        guard burstAnalysisGeneration == generation else { return }
        burstAnalysisTask = nil
        burstAnalysisProgress = BurstAnalysisProgress()
    }

    /// Clear loaded burst analysis artifacts, delete the saved burst cache for
    /// the current catalog, and run a fresh analysis pass.
    func reindexBurstAnalysis() async {
        guard let catalog = selectedSource?.url, !files.isEmpty else { return }

        clearLoadedBurstAnalysisForReindex()
        await burstAnalysisCache.delete(catalog: catalog)
        await analyzeBursts()
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

    var isDeepAIReviewUnavailable: Bool {
        !deepAIReviewFeature.availability.isAvailable
            || sharpnessModel.isScoring
            || similarityModel.isIndexing
            || similarityModel.isGrouping
            || burstAnalysisProgress.isRunning
            || deepAIReviewFeature.isRunning
    }

    func deepAIReviewResult(for groupFiles: [FileItem]) -> DeepAIReviewResult? {
        guard let signature = BurstGroupSignature(
            files: groupFiles,
            catalog: selectedSource?.url,
        ) else { return nil }
        return deepAIReviewFeature.result(for: signature)
    }

    func startDeepAIReview(for groupFiles: [FileItem]) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.startDeepAIReview(): requested Deep Review for \(groupFiles.count) files",
        )
        guard !isDeepAIReviewUnavailable else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.startDeepAIReview(): skipped because Deep Review is unavailable or another analysis is running",
            )
            return
        }
        guard let request = deepAIReviewRequest(for: groupFiles) else {
            Logger.process.debugMessageOnly(
                "RawCullViewModel.startDeepAIReview(): skipped because the review request could not be created",
            )
            return
        }
        await deepAIReviewFeature.start(request)
        Logger.process.debugMessageOnly(
            "RawCullViewModel.startDeepAIReview(): Deep Review task returned",
        )
    }

    func cancelDeepAIReview() {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.cancelDeepAIReview(): cancelling Deep Review",
        )
        deepAIReviewFeature.cancel()
    }

    func applyDeepAIReviewRecommendation(
        _ result: DeepAIReviewResult,
        to groupFiles: [FileItem],
    ) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.applyDeepAIReviewRecommendation(): applying the Deep Review recommendation",
        )
        let groupID = groupID(for: groupFiles)
        guard let selectedSource,
              groupID >= 0,
              result.groupSignature == BurstGroupSignature(
                  files: groupFiles,
                  catalog: selectedSource.url,
              ),
              let winner = result.recommendedFileID.flatMap({ id in
                  groupFiles.first { $0.id == id }
              })
        else { return }

        let override = BurstWinnerOverride(
            winnerFileName: winner.name,
            memberFileNames: groupFiles.map(\.name),
        )
        cullingModel.upsertBurstWinnerOverride(override, in: selectedSource.url)
        applyManualWinnerOverrides(files: files)
        updateRating(for: winner, rating: 3)
        markBurstGroupReviewed(groupID: groupID)
    }

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
        guard let currentIndex = similarityModel.burstGroups.firstIndex(where: { $0.id == currentGroupID })
        else { return false }

        let currentGroup = similarityModel.burstGroups[currentIndex]

        let eligibleGroupIDs = Set(
            filteredBurstGroupsForReviewQueue
                .filter { $0.fileIDs.count > 1 }
                .map(\.id),
        )
        guard let nextGroup = similarityModel.burstGroups
            .dropFirst(currentIndex + 1)
            .first(where: { $0.fileIDs.count > 1 && eligibleGroupIDs.contains($0.id) })
        else { return false }

        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
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
        let savedRankedIDs = burstAnalysisResults[groupID]?.candidates.map(\.fileID)
        let rankedIDs = if let savedRankedIDs, !savedRankedIDs.isEmpty {
            savedRankedIDs
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
        cullingModel.applyRatings(entry.previousRatingsByFileName, in: selectedSource.url)
        rebuildRatingCache()
        lastBurstUndoEntry = nil
        if var result = burstAnalysisResults[entry.groupID] {
            result.reviewState = burstReviewStates[entry.groupID] ?? .none
            burstAnalysisResults[entry.groupID] = result
        }
    }

    // MARK: - Review queue

    var burstReviewQueueCounts: BurstReviewQueueCounts {
        BurstReviewQueuePolicy.counts(for: burstAnalysisResults.values)
    }

    var burstGroupsHomeCounts: BurstGroupsHomeCounts {
        let reviewCounts = burstReviewQueueCounts
        return BurstGroupsHomeCounts(
            singleImages: similarityModel.burstGroups.reduce(into: 0) { count, group in
                if group.fileIDs.count == 1 {
                    count += 1
                }
            },
            deferred: reviewCounts.deferred,
            markedReviewed: burstAnalysisResults.values.count { result in
                result.fileIDs.count > 1 && result.reviewState == .reviewed
            },
            needsReview: reviewCounts.needsReview,
        )
    }

    var hasCompletedBurstAnalysis: Bool {
        completedBurstAnalysisContext != nil
            && !burstAnalysisProgress.isRunning
            && !similarityModel.isGrouping
    }

    var filteredBurstGroupsForReviewQueue: [BurstGroup] {
        switch burstReviewQueueFilter {
        case .all:
            return similarityModel.burstGroups

        case .singleImages:
            return similarityModel.burstGroups.filter { $0.fileIDs.count == 1 }

        case .needsReview, .deferred, .markedReviewed, .reviewed:
            break
        }

        return similarityModel.burstGroups.filter { group in
            guard group.fileIDs.count > 1 else { return false }
            guard let result = burstAnalysisResults[group.id] else { return false }
            return BurstReviewQueuePolicy.includes(result, filter: burstReviewQueueFilter)
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
        let targets: [FileItem]
        if !selectedFileIDs.isEmpty {
            targets = files.filter { selectedFileIDs.contains($0.id) }
        } else if case let .stars(rating) = ratingFilter {
            let visible = filteredFiles.isEmpty ? files : filteredFiles
            targets = visible.filter { getRating(for: $0) == rating }
        } else {
            targets = files
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
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let results = BurstRankingEngine.rank(
            groups: similarityModel.burstGroups.filter { $0.fileIDs.count > 1 },
            filesByID: filesByID,
            scores: sharpnessModel.scores,
            maxScore: sharpnessModel.maxScore,
            saliencyInfo: sharpnessModel.saliencyInfo,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            reviewStates: burstReviewStates,
        )
        burstAnalysisResults = Dictionary(uniqueKeysWithValues: results.map { ($0.groupID, $0) })
        applyManualWinnerOverrides(files: files)
    }

    private func groupID(for groupFiles: [FileItem]) -> Int {
        groupFiles.lazy.compactMap { self.similarityModel.burstGroupLookup[$0.id] }.first ?? -1
    }

    private func deepAIReviewRequest(
        for groupFiles: [FileItem],
    ) -> DeepAIReviewRequest? {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.deepAIReviewRequest(): building a request from \(groupFiles.count) files",
        )
        guard let catalog = selectedSource?.url,
              let signature = BurstGroupSignature(files: groupFiles, catalog: catalog)
        else { return nil }
        let groupID = groupID(for: groupFiles)
        guard groupID >= 0 else { return nil }

        let rankedIDs = burstAnalysisResults[groupID]?.candidates.map(\.fileID) ?? []
        let ranks = Dictionary(
            uniqueKeysWithValues: rankedIDs.enumerated().map { index, id in
                (id, index + 1)
            },
        )
        let fallbackRanks = Dictionary(
            uniqueKeysWithValues: groupFiles.enumerated().map { index, file in
                (file.id, index + 1)
            },
        )
        let candidates = groupFiles.map { file in
            DeepAIReviewInputCandidate(
                fileID: file.id,
                fileName: file.name,
                url: file.url,
                burstRank: ranks[file.id] ?? fallbackRanks[file.id] ?? 1,
                normalSharpnessScore: sharpnessModel.scores[file.id],
                subjectLabel: sharpnessModel.saliencyInfo[file.id]?.subjectLabel,
                normalizedAFPoint: file.afFocusNormalized,
            )
        }
        let request = DeepAIReviewRequest(
            groupID: groupID,
            groupSignature: signature,
            candidates: candidates,
            preset: deepAIReviewFeature.preset,
            scoringSource: sharpnessModel.scoringSource,
        )
        Logger.process.debugMessageOnly(
            "RawCullViewModel.deepAIReviewRequest(): created request for group \(groupID) with \(candidates.count) candidates",
        )
        return request
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
            previousRatingsByFileName: Dictionary(uniqueKeysWithValues: files.map { ($0.name, getRating(for: $0)) }),
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

    private func applyCachedBurstAnalysis(
        _ snapshot: BurstAnalysisCacheSnapshot,
        catalog: URL,
        files: [FileItem],
        generation: Int,
    ) {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.applyCachedBurstAnalysis(): applying cached results for \(files.count) files",
        )
        similarityModel.applyCachedBurstAnalysis(snapshot)
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: snapshot.sharpnessScores,
            preloadedSaliency: snapshot.saliencyInfo,
        )
        burstReviewStates = cachedReviewStates(from: snapshot, files: files)
        burstAnalysisResults = Dictionary(uniqueKeysWithValues: snapshot.results.map { result in
            var updated = result
            updated.reviewState = burstReviewStates[result.groupID] ?? .none
            return (updated.groupID, updated)
        })
        applyManualWinnerOverrides(files: files)
        completedBurstAnalysisContext = makeCompletedBurstAnalysisContext(
            catalog: catalog,
            files: files,
            generation: generation,
        )
    }

    func clearLoadedBurstAnalysisForReindex() {
        cancelAndResetBurstAnalysis()
    }

    func cancelAndResetBurstAnalysis() {
        deepAIReviewFeature.reset()
        burstAnalysisTask?.cancel()
        burstAnalysisTask = nil
        burstAnalysisGeneration &+= 1
        completedBurstAnalysisContext = nil
        burstAnalysisProgress = BurstAnalysisProgress()
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
    ) async {
        Logger.process.debugMessageOnly(
            "RawCullViewModel.saveBurstAnalysisCache(): preparing a snapshot for \(files.count) files",
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog),
              let context = completedBurstAnalysisContext,
              context.generation == generation,
              context.similaritySignature == currentBurstSimilaritySignature
        else { return }

        let snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: BurstAnalysisCache.schemaVersion,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
            sharpnessSignature: currentBurstSharpnessSignature,
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
        )
        guard isCurrentBurstAnalysis(generation: generation, catalog: catalog) else { return }
        await burstAnalysisCacheSave(snapshot, catalog)
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

    private func remapCachedSnapshot(
        _ snapshot: BurstAnalysisCacheSnapshot,
        to currentFiles: [FileItem],
    ) -> BurstAnalysisCacheSnapshot {
        let cachedFilesByID = Dictionary(uniqueKeysWithValues: snapshot.files.map { ($0.id, $0) })
        let currentByPath = Dictionary(uniqueKeysWithValues: currentFiles.map { ($0.url.path, $0.id) })
        var idMap: [UUID: UUID] = [:]
        for (oldID, cachedFile) in cachedFilesByID {
            if let currentID = currentByPath[cachedFile.path] {
                idMap[oldID] = currentID
            }
        }

        func remap(_ id: UUID) -> UUID {
            idMap[id] ?? id
        }

        let groups = snapshot.groups.map { group in
            BurstGroup(id: group.id, fileIDs: group.fileIDs.map(remap))
        }
        let evidence = snapshot.boundaryEvidence.map { item in
            BurstBoundaryEvidence(
                previousID: remap(item.previousID),
                currentID: remap(item.currentID),
                visualDistance: item.visualDistance,
                timeGapSeconds: item.timeGapSeconds,
                captureTimeUsedFallback: item.captureTimeUsedFallback,
                focalLengthDelta: item.focalLengthDelta,
                exposureAdjustmentEV: item.exposureAdjustmentEV,
                exposureChanged: item.exposureChanged,
                cameraChanged: item.cameraChanged,
                lensChanged: item.lensChanged,
                startsNewGroup: item.startsNewGroup,
                reasons: item.reasons,
            )
        }
        let results = snapshot.results.map { result in
            BurstAnalysisResult(
                groupID: result.groupID,
                fileIDs: result.fileIDs.map(remap),
                candidates: result.candidates.map { candidate in
                    BurstCandidateScore(
                        fileID: remap(candidate.fileID),
                        overallScore: candidate.overallScore,
                        sharpnessComponent: candidate.sharpnessComponent,
                        burstRelativeSharpnessComponent: candidate.burstRelativeSharpnessComponent,
                        focusPointComponent: candidate.focusPointComponent,
                        saliencyComponent: candidate.saliencyComponent,
                        metadataComponent: candidate.metadataComponent,
                        confidence: candidate.confidence,
                        reasons: candidate.reasons,
                        cautions: candidate.cautions,
                    )
                },
                recommendedFileID: result.recommendedFileID.map(remap),
                secondBestFileID: result.secondBestFileID.map(remap),
                confidence: result.confidence,
                reviewState: result.reviewState,
                isSafeForOneClickCulling: result.isSafeForOneClickCulling,
                reasons: result.reasons,
                cautions: result.cautions,
            )
        }

        return BurstAnalysisCacheSnapshot(
            schemaVersion: snapshot.schemaVersion,
            algorithmVersion: snapshot.algorithmVersion,
            catalogPath: snapshot.catalogPath,
            thumbnailMaxPixelSize: snapshot.thumbnailMaxPixelSize,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
            files: currentFiles.map {
                BurstAnalysisCacheFile(id: $0.id, path: $0.url.path, size: $0.size, modificationDate: $0.dateModified)
            },
            embeddings: Dictionary(uniqueKeysWithValues: snapshot.embeddings.compactMap { oldID, data in
                guard let currentID = idMap[oldID] else { return nil }
                return (currentID, data)
            }),
            sharpnessScores: Dictionary(uniqueKeysWithValues: snapshot.sharpnessScores.compactMap { oldID, score in
                guard let currentID = idMap[oldID] else { return nil }
                return (currentID, score)
            }),
            saliencyInfo: Dictionary(uniqueKeysWithValues: snapshot.saliencyInfo.compactMap { oldID, info in
                guard let currentID = idMap[oldID] else { return nil }
                return (currentID, info)
            }),
            groups: groups,
            boundaryEvidence: evidence,
            results: results,
            reviewStateSnapshots: snapshot.reviewStateSnapshots,
        )
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
            artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
            embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
            embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
        )
    }

    private func makeCompletedBurstAnalysisContext(
        catalog: URL,
        files: [FileItem],
        generation: Int,
    ) -> CompletedBurstAnalysisContext {
        CompletedBurstAnalysisContext(
            catalog: catalog,
            orderedFileIDs: files.map(\.id),
            orderedFilePaths: files.map(\.url.path),
            similaritySignature: currentBurstSimilaritySignature,
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
