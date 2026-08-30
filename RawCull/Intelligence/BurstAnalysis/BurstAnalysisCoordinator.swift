import Foundation
import Observation
import OSLog
import PhotoAIContracts
import RawCullCore

/// Owns burst worker orchestration while application state and culling commands
/// remain in `RawCullViewModel`.
@MainActor
struct BurstAnalysisRunCallbacks {
    let isCurrent: () -> Bool
    let updateProgress: (BurstAnalysisProgress) -> Void
    let didScoreSharpness: ([FileItem]) async -> Void
    let applyResult: (BurstAnalysisPipelineResult) -> BurstAnalysisPipelineResult?
}

@MainActor
@Observable
final class BurstAnalysisCoordinator {
    private let sharpnessModel: SharpnessScoringModel
    private let similarityFeature: RawCullSimilarityFeature
    private let similarityModel: SimilarityScoringModel
    private let cacheRepository: any BurstAnalysisCacheRepository
    var progress = BurstAnalysisProgress()
    var generation = 0
    @ObservationIgnored var task: Task<Void, Never>?

    var hasActiveTask: Bool {
        task != nil
    }

    init(
        sharpnessModel: SharpnessScoringModel,
        similarityFeature: RawCullSimilarityFeature,
        similarityModel: SimilarityScoringModel,
        cacheRepository: any BurstAnalysisCacheRepository,
    ) {
        self.sharpnessModel = sharpnessModel
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.cacheRepository = cacheRepository
    }

    /// Run cache preparation and every burst worker step from one immutable
    /// request. Application state is published only through `applyResult`, after
    /// the caller's generation/catalog validity check succeeds.
    func run(
        request: BurstAnalysisPipelineRequest,
        initialReviewStates: [Int: BurstReviewState],
        fullCatalogFileIDs: Set<UUID>,
        callbacks: BurstAnalysisRunCallbacks,
    ) async -> BurstAnalysisPipelineResult? {
        let files = request.orderedFiles
        guard callbacks.isCurrent() else { return nil }

        callbacks.updateProgress(BurstAnalysisProgress(step: .loadingCache))
        guard let preparation = await prepareCache(
            for: request,
            importLegacyCandidate: true,
            isCurrent: { callbacks.isCurrent() },
        ) else { return nil }

        var diagnostics = preparation.diagnostics
        if let snapshot = preparation.compatibleSnapshot {
            return applyCachedResult(
                snapshot: snapshot,
                preparation: preparation,
                files: files,
                callbacks: callbacks,
            )
        }

        await diagnostics.append(prepareSharpness(files: files, callbacks: callbacks))
        guard callbacks.isCurrent() else { return nil }
        await diagnostics.append(prepareSimilarity(files: files, callbacks: callbacks))

        guard callbacks.isCurrent() else { return nil }
        callbacks.updateProgress(BurstAnalysisProgress(step: .grouping))
        await similarityModel.groupBursts(
            files: files,
            configuration: request.configuration.grouping,
        )

        guard callbacks.isCurrent() else { return nil }
        let restoredReviewStates: [Int: BurstReviewState] = if let migrationCandidate = preparation.migrationCandidate {
            Self.restoredReviewStates(
                snapshots: migrationCandidate.reviewStateSnapshots,
                groups: similarityModel.burstGroups,
                files: files,
                catalog: request.catalogIdentity,
            )
        } else {
            initialReviewStates
        }

        callbacks.updateProgress(BurstAnalysisProgress(step: .ranking))
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let rankings = BurstRankingEngine.rank(
            groups: similarityModel.burstGroups.filter { $0.fileIDs.count > 1 },
            filesByID: filesByID,
            scores: sharpnessModel.scores,
            maxScore: sharpnessModel.maxScore,
            saliencyInfo: sharpnessModel.saliencyInfo,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            reviewStates: restoredReviewStates,
        )
        let workerResult = BurstAnalysisPipelineResult(
            groups: similarityModel.burstGroups,
            rankings: rankings,
            restoredReviewStates: restoredReviewStates,
            cacheOutcome: preparation.cacheOutcome,
            diagnostics: diagnostics,
        )

        guard callbacks.isCurrent(),
              let appliedResult = callbacks.applyResult(workerResult)
        else { return nil }
        callbacks.updateProgress(BurstAnalysisProgress(step: .savingCache))
        if Set(files.map(\.id)) == fullCatalogFileIDs {
            let snapshot = makeCacheSnapshot(
                request: request,
                result: appliedResult,
            )
            guard callbacks.isCurrent() else { return nil }
            await cacheRepository.save(snapshot, catalog: request.catalogIdentity)
        }
        diagnostics.append(.cacheSaveRequested)
        return BurstAnalysisPipelineResult(
            groups: appliedResult.groups,
            rankings: appliedResult.rankings,
            restoredReviewStates: appliedResult.restoredReviewStates,
            cacheOutcome: appliedResult.cacheOutcome,
            diagnostics: diagnostics,
        )
    }

    private func applyCachedResult(
        snapshot: BurstAnalysisCacheSnapshot,
        preparation: BurstAnalysisCachePreparation,
        files: [FileItem],
        callbacks: BurstAnalysisRunCallbacks,
    ) -> BurstAnalysisPipelineResult? {
        Logger.process.debugMessageOnly(
            "BurstAnalysisCoordinator.run(): cache hit; applying cached analysis",
        )
        applyCachedWorkerState(snapshot, files: files)
        guard callbacks.isCurrent() else { return nil }
        let reviewStates = preparation.restoredReviewStates
        let result = BurstAnalysisPipelineResult(
            groups: snapshot.groups,
            rankings: snapshot.results.map { ranking in
                var updated = ranking
                updated.reviewState = reviewStates[ranking.groupID] ?? .none
                return updated
            }.sorted { $0.groupID < $1.groupID },
            restoredReviewStates: reviewStates,
            cacheOutcome: preparation.cacheOutcome,
            diagnostics: preparation.diagnostics,
        )
        return callbacks.applyResult(result)
    }

    private func prepareSharpness(
        files: [FileItem],
        callbacks: BurstAnalysisRunCallbacks,
    ) async -> BurstAnalysisDiagnostic {
        guard files.contains(where: { sharpnessModel.scores[$0.id] == nil }) else {
            return .reusedSharpnessScores
        }

        callbacks.updateProgress(
            BurstAnalysisProgress(step: .scoringSharpness, total: files.count),
        )
        let shouldScore = await sharpnessModel.calibrateFromBurst(files)
        guard callbacks.isCurrent(), shouldScore else { return .scoredMissingSharpness }
        await sharpnessModel.scoreFiles(files)
        guard callbacks.isCurrent() else { return .scoredMissingSharpness }
        await callbacks.didScoreSharpness(files)
        return .scoredMissingSharpness
    }

    private func prepareSimilarity(
        files: [FileItem],
        callbacks: BurstAnalysisRunCallbacks,
    ) async -> BurstAnalysisDiagnostic {
        guard files.contains(where: { similarityModel.embeddings[$0.id] == nil }) else {
            return .reusedSimilarityArtifacts
        }

        callbacks.updateProgress(
            BurstAnalysisProgress(step: .indexingSimilarity, total: files.count),
        )
        await similarityFeature.indexBurstFiles(files)
        return .indexedMissingSimilarityArtifacts
    }

    /// Hydrate current per-file artifacts, import a compatible legacy candidate
    /// when requested, and decide whether the derived cache is reusable.
    ///
    /// The validity callback preserves the view model's generation and catalog
    /// checks at every suspension point without giving the coordinator ownership
    /// of application selection state.
    func prepareCache(
        for request: BurstAnalysisPipelineRequest,
        importLegacyCandidate: Bool,
        isCurrent: @MainActor () -> Bool,
    ) async -> BurstAnalysisCachePreparation? {
        guard isCurrent() else { return nil }
        await similarityFeature.hydrateBurstArtifacts(request.orderedFiles)
        guard isCurrent() else { return nil }

        var diagnostics: [BurstAnalysisDiagnostic] = []
        var migrationCandidate: BurstAnalysisCacheSnapshot?
        if importLegacyCandidate,
           let loadedCandidate = await cacheRepository.loadMigrationCandidate(
               catalog: request.catalogIdentity,
           ) {
            guard isCurrent() else { return nil }
            let remappedCandidate = Self.remap(
                loadedCandidate,
                to: request.orderedFiles,
            )
            migrationCandidate = remappedCandidate
            diagnostics.append(.legacyMigrationCandidateFound)
            _ = await similarityModel.importLegacyArtifacts(
                remappedCandidate.embeddings,
                files: request.orderedFiles,
                signature: remappedCandidate.similaritySignature,
            )
            guard isCurrent() else { return nil }
        }

        let loadedSnapshot = await cacheRepository.load(
            catalog: request.catalogIdentity,
            files: request.orderedFiles,
            thumbnailMaxPixelSize: request.configuration.thumbnailMaxPixelSize,
            sharpnessSignature: request.sharpnessSignature,
            similaritySignature: request.similaritySignature,
        )
        guard isCurrent() else { return nil }
        guard let loadedSnapshot else {
            return BurstAnalysisCachePreparation(
                compatibleSnapshot: nil,
                migrationCandidate: migrationCandidate,
                restoredReviewStates: [:],
                cacheOutcome: .miss,
                diagnostics: diagnostics,
            )
        }

        let snapshot = Self.remap(loadedSnapshot, to: request.orderedFiles)
        let currentDigest = BurstAnalysisCache.artifactSetDigest(
            files: request.orderedFiles,
            artifacts: similarityModel.embeddings,
        )
        guard snapshot.similarityArtifactSetDigest == currentDigest else {
            return BurstAnalysisCachePreparation(
                compatibleSnapshot: nil,
                migrationCandidate: migrationCandidate,
                restoredReviewStates: [:],
                cacheOutcome: .rejectedArtifactSet,
                diagnostics: diagnostics,
            )
        }

        return BurstAnalysisCachePreparation(
            compatibleSnapshot: snapshot,
            migrationCandidate: migrationCandidate,
            restoredReviewStates: Self.restoredReviewStates(
                snapshots: snapshot.reviewStateSnapshots,
                groups: snapshot.groups,
                files: request.orderedFiles,
                catalog: request.catalogIdentity,
            ),
            cacheOutcome: .hit,
            diagnostics: diagnostics,
        )
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        await cacheRepository.save(snapshot, catalog: catalog)
    }

    func applyCachedWorkerState(
        _ snapshot: BurstAnalysisCacheSnapshot,
        files: [FileItem],
    ) {
        similarityModel.applyCachedBurstAnalysis(snapshot)
        sharpnessModel.applyPreloadedScores(
            files,
            preloadedScores: snapshot.sharpnessScores,
            preloadedSaliency: snapshot.saliencyInfo,
        )
    }

    func deleteCache(catalog: URL) async {
        await cacheRepository.delete(catalog: catalog)
    }

    private func makeCacheSnapshot(
        request: BurstAnalysisPipelineRequest,
        result: BurstAnalysisPipelineResult,
    ) -> BurstAnalysisCacheSnapshot {
        let files = request.orderedFiles
        return BurstAnalysisCacheSnapshot(
            schemaVersion: request.configuration.cacheSchemaVersion,
            algorithmVersion: request.configuration.groupingAlgorithmVersion,
            catalogPath: request.catalogIdentity.path,
            thumbnailMaxPixelSize: request.configuration.thumbnailMaxPixelSize,
            sharpnessSignature: request.sharpnessSignature,
            similaritySignature: request.similaritySignature,
            files: files.map {
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: Self.scoped(similarityModel.embeddings, to: files),
            sharpnessScores: Self.scoped(sharpnessModel.scores, to: files),
            saliencyInfo: Self.scoped(sharpnessModel.saliencyInfo, to: files),
            groups: result.groups,
            boundaryEvidence: similarityModel.burstBoundaryEvidence,
            results: result.rankings.sorted { $0.groupID < $1.groupID },
            reviewStateSnapshots: Self.reviewStateSnapshots(
                result.restoredReviewStates,
                groups: result.groups,
                files: files,
                catalog: request.catalogIdentity,
            ),
            similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
                files: files,
                artifacts: similarityModel.embeddings,
            ),
        )
    }

    private nonisolated static func scoped<Value>(
        _ values: [UUID: Value],
        to files: [FileItem],
    ) -> [UUID: Value] {
        let ids = Set(files.map(\.id))
        return values.filter { ids.contains($0.key) }
    }

    private nonisolated static func reviewStateSnapshots(
        _ states: [Int: BurstReviewState],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [BurstReviewStateSnapshot] {
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return groups.compactMap { group in
            guard let state = states[group.id],
                  state != .none,
                  let signature = BurstGroupSignature(
                      files: group.fileIDs.compactMap { filesByID[$0] },
                      catalog: catalog,
                  )
            else { return nil }
            return BurstReviewStateSnapshot(signature: signature, state: state)
        }
    }
}
