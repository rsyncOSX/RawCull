//
//  RawCullViewModel+BurstGrouping.swift
//  RawCull
//

import Foundation
import RawCullCore

/// Precomputed "best frame" info for a burst group — consumed by the
/// grid's burst-section header so the header body does no scoring math
/// on redraw.
struct BestInGroupInfo: Equatable {
    let fileName: String
    /// Percentage of `maxScore`, or nil when scores are missing or maxScore ≤ 0.
    let percent: Int?
    let isManualWinner: Bool
}

extension RawCullViewModel {
    // MARK: - Intelligent burst analysis

    /// Run the full intelligent burst analysis pipeline: load cache when valid,
    /// score sharpness, index similarity, group bursts, rank candidates, and
    /// persist the analysis artifacts.
    func analyzeBursts() async {
        guard let catalog = selectedSource?.url, !files.isEmpty else { return }

        burstAnalysisTask?.cancel()
        burstAnalysisTask = Task {}

        let sorted = burstOrderedFiles
        burstAnalysisProgress = BurstAnalysisProgress(step: .loadingCache)
        if let snapshot = await burstAnalysisCache.load(
            catalog: catalog,
            files: sorted,
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
            sharpnessSignature: currentBurstSharpnessSignature,
        ) {
            applyCachedBurstAnalysis(remapCachedSnapshot(snapshot, to: sorted))
            burstAnalysisProgress = BurstAnalysisProgress()
            return
        }

        guard !Task.isCancelled else { return }
        if sharpnessModel.scores.isEmpty {
            burstAnalysisProgress = BurstAnalysisProgress(
                step: .scoringSharpness,
                total: sorted.count,
            )
            await calibrateAndScoreCurrentCatalog()
        }

        guard !Task.isCancelled else { return }
        if similarityModel.embeddings.count < sorted.count {
            burstAnalysisProgress = BurstAnalysisProgress(
                step: .indexingSimilarity,
                total: sorted.count,
            )
            await similarityModel.indexFiles(sorted)
        }

        guard !Task.isCancelled else { return }
        burstAnalysisProgress = BurstAnalysisProgress(step: .grouping)
        await similarityModel.groupBursts(files: sorted)

        guard !Task.isCancelled else { return }
        burstAnalysisProgress = BurstAnalysisProgress(step: .ranking)
        recomputeBurstRankings(files: sorted)

        guard !Task.isCancelled else { return }
        burstAnalysisProgress = BurstAnalysisProgress(step: .savingCache)
        await saveBurstAnalysisCache(catalog: catalog, files: sorted)
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
        let sorted = burstOrderedFiles
        guard !Task.isCancelled else { return }
        await similarityModel.groupBursts(files: sorted)
        recomputeBurstRankings(files: sorted)
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

    func setManualBurstWinner(_ winner: FileItem, in groupFiles: [FileItem]) {
        guard let selectedSource,
              groupFiles.contains(where: { $0.id == winner.id })
        else { return }

        let override = BurstWinnerOverride(
            winnerFileName: winner.name,
            memberFileNames: groupFiles.map(\.name),
        )
        cullingModel.upsertBurstWinnerOverride(override, in: selectedSource.url)
        updateRating(for: winner, rating: 3)
        applyManualWinnerOverrides(files: files)
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
        activeBurstComparisonGroupID = groupID
        let rankedIDs = burstAnalysisResults[groupID]?.candidates.map(\.fileID) ?? groupFiles.map(\.id)
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

    var filteredBurstGroupsForReviewQueue: [BurstGroup] {
        guard burstReviewQueueFilter != .all else { return similarityModel.burstGroups }
        return similarityModel.burstGroups.filter { group in
            guard let result = burstAnalysisResults[group.id] else { return false }
            return BurstReviewQueuePolicy.includes(result, filter: burstReviewQueueFilter)
        }
    }

    func markBurstGroupNeedsReview(groupID: Int) {
        setBurstReviewState(.needsReview, groupID: groupID)
    }

    func markBurstGroupReviewed(groupID: Int) {
        setBurstReviewState(.reviewed, groupID: groupID)
    }

    func deferBurstGroup(groupID: Int) {
        setBurstReviewState(.deferred, groupID: groupID)
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

    /// Compute the precomputed display info for a burst group's "best" frame.
    /// Returns nil when scores are empty or the group is empty.
    ///
    /// `percent` is `Int(min(score / maxScore, 1.0) · 100)` — i.e. the
    /// best frame's sharpness as a percentage of the catalog-wide
    /// normalization denominator (`SharpnessScoringModel.maxScore`, the
    /// p90 of all scores for n ≥ 10). Clamped to `≤ 100` so a score that
    /// happens to exceed the p90 doesn't render above 100 %.
    nonisolated static func bestInGroupInfo(
        files: [FileItem],
        scores: [UUID: Float],
        maxScore: Float,
    ) -> BestInGroupInfo? {
        guard !scores.isEmpty, let best = sharpestFile(in: files, scores: scores) else { return nil }
        return bestInGroupInfo(file: best, scores: scores, maxScore: maxScore, isManualWinner: false)
    }

    nonisolated static func bestInGroupInfo(
        file: FileItem,
        scores: [UUID: Float],
        maxScore: Float,
        isManualWinner: Bool,
    ) -> BestInGroupInfo {
        let percent: Int? = if let score = scores[file.id], maxScore > 0 {
            Int(min(score / maxScore, 1.0) * 100)
        } else {
            nil
        }
        return BestInGroupInfo(
            fileName: file.name,
            percent: percent,
            isManualWinner: isManualWinner,
        )
    }

    func burstAnalysisResult(for groupID: Int) -> BurstAnalysisResult? {
        burstAnalysisResults[groupID]
    }

    func burstCandidate(for file: FileItem) -> BurstCandidateScore? {
        guard let groupID = similarityModel.burstGroupLookup[file.id] else { return nil }
        return burstAnalysisResults[groupID]?.candidates.first { $0.fileID == file.id }
    }

    private var burstOrderedFiles: [FileItem] {
        files.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func recomputeBurstRankings(files: [FileItem]) {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let results = BurstRankingEngine.rank(
            groups: similarityModel.burstGroups,
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
            validFileNames: Set(files.map(\.name)),
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
        burstReviewStates[groupID] = state
        if var result = burstAnalysisResults[groupID] {
            result.reviewState = state
            burstAnalysisResults[groupID] = result
        }
        if persist {
            persistBurstReviewStates()
        }
    }

    private func persistBurstReviewStates() {
        guard let catalog = selectedSource?.url else { return }
        let currentFiles = burstOrderedFiles
        Task {
            await saveBurstAnalysisCache(catalog: catalog, files: currentFiles)
        }
    }

    private func applyCachedBurstAnalysis(_ snapshot: BurstAnalysisCacheSnapshot) {
        similarityModel.applyCachedBurstAnalysis(snapshot)
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: snapshot.sharpnessScores,
            preloadedSaliency: snapshot.saliencyInfo,
        )
        burstReviewStates = cachedReviewStates(from: snapshot)
        burstAnalysisResults = Dictionary(uniqueKeysWithValues: snapshot.results.map { result in
            var updated = result
            updated.reviewState = burstReviewStates[result.groupID] ?? .none
            return (updated.groupID, updated)
        })
        applyManualWinnerOverrides(files: files)
    }

    func clearLoadedBurstAnalysisForReindex() {
        burstAnalysisTask?.cancel()
        burstAnalysisTask = nil
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

    private func saveBurstAnalysisCache(catalog: URL, files: [FileItem]) async {
        let snapshot = BurstAnalysisCacheSnapshot(
            schemaVersion: BurstAnalysisCache.schemaVersion,
            algorithmVersion: BurstGroupingConfig.algorithmVersion,
            catalogPath: catalog.path,
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
            sharpnessSignature: currentBurstSharpnessSignature,
            files: files.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: similarityModel.embeddings,
            sharpnessScores: sharpnessModel.scores,
            saliencyInfo: sharpnessModel.saliencyInfo,
            groups: similarityModel.burstGroups,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            results: Array(burstAnalysisResults.values).sorted { $0.groupID < $1.groupID },
            reviewStateSnapshots: reviewStateSnapshots(catalog: catalog, files: files),
        )
        await burstAnalysisCache.save(snapshot, catalog: catalog)
    }

    func cachedReviewStates(from snapshot: BurstAnalysisCacheSnapshot) -> [Int: BurstReviewState] {
        guard let catalog = selectedSource?.url else { return [:] }
        let savedStatesBySignature = Dictionary(
            uniqueKeysWithValues: snapshot.reviewStateSnapshots.map { ($0.signature, $0.state) },
        )
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })

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
                focalLengthDelta: item.focalLengthDelta,
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
}
