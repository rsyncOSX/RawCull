import Foundation
import PhotoAIContracts
import RawCullCore

/// Narrow repository boundary for the derived burst cache. Disk work remains
/// actor-isolated in `BurstAnalysisCache`; this main-actor adapter keeps the
/// coordinator independently replaceable in tests.
@MainActor
protocol BurstAnalysisCacheRepository: AnyObject {
    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot?

    func loadMigrationCandidate(catalog: URL) async -> BurstAnalysisCacheSnapshot?
    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async
    func delete(catalog: URL) async
}

@MainActor
final class LiveBurstAnalysisCacheRepository: BurstAnalysisCacheRepository {
    private let cache: BurstAnalysisCache

    init(cache: BurstAnalysisCache = .shared) {
        self.cache = cache
    }

    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
    }

    func loadMigrationCandidate(catalog: URL) async -> BurstAnalysisCacheSnapshot? {
        await cache.loadMigrationCandidate(catalog: catalog)
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        await cache.save(snapshot, catalog: catalog)
    }

    func delete(catalog: URL) async {
        await cache.delete(catalog: catalog)
    }
}

/// Owns burst worker orchestration while application state and culling commands
/// remain in `RawCullViewModel`.
@MainActor
final class BurstAnalysisCoordinator {
    private let similarityFeature: RawCullSimilarityFeature
    private let similarityModel: SimilarityScoringModel
    private let cacheRepository: any BurstAnalysisCacheRepository

    init(
        similarityFeature: RawCullSimilarityFeature,
        similarityModel: SimilarityScoringModel,
        cacheRepository: any BurstAnalysisCacheRepository,
    ) {
        self.similarityFeature = similarityFeature
        self.similarityModel = similarityModel
        self.cacheRepository = cacheRepository
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
           )
        {
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

    func deleteCache(catalog: URL) async {
        await cacheRepository.delete(catalog: catalog)
    }

    nonisolated static func restoredReviewStates(
        snapshots: [BurstReviewStateSnapshot],
        groups: [BurstGroup],
        files: [FileItem],
        catalog: URL,
    ) -> [Int: BurstReviewState] {
        let savedStates = Dictionary(
            uniqueKeysWithValues: snapshots.map { ($0.signature, $0.state) },
        )
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        return Dictionary(uniqueKeysWithValues: groups.compactMap { group in
            let groupFiles = group.fileIDs.compactMap { filesByID[$0] }
            guard let signature = BurstGroupSignature(
                files: groupFiles,
                catalog: catalog,
            ),
                let state = savedStates[signature],
                state != .none
            else { return nil }
            return (group.id, state)
        })
    }

    nonisolated static func remap(
        _ snapshot: BurstAnalysisCacheSnapshot,
        to currentFiles: [FileItem],
    ) -> BurstAnalysisCacheSnapshot {
        let cachedFilesByID = Dictionary(
            uniqueKeysWithValues: snapshot.files.map { ($0.id, $0) },
        )
        let currentByPath = Dictionary(
            uniqueKeysWithValues: currentFiles.map { ($0.url.path, $0.id) },
        )
        let idMap = Dictionary(uniqueKeysWithValues: cachedFilesByID.compactMap { oldID, file in
            currentByPath[file.path].map { (oldID, $0) }
        })

        func remapID(_ id: UUID) -> UUID {
            idMap[id] ?? id
        }

        let groups = snapshot.groups.map { group in
            BurstGroup(id: group.id, fileIDs: group.fileIDs.map(remapID))
        }
        let evidence = snapshot.boundaryEvidence.map { item in
            BurstBoundaryEvidence(
                previousID: remapID(item.previousID),
                currentID: remapID(item.currentID),
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
                fileIDs: result.fileIDs.map(remapID),
                candidates: result.candidates.map { candidate in
                    BurstCandidateScore(
                        fileID: remapID(candidate.fileID),
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
                recommendedFileID: result.recommendedFileID.map(remapID),
                secondBestFileID: result.secondBestFileID.map(remapID),
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
                BurstAnalysisCacheFile(
                    id: $0.id,
                    path: $0.url.path,
                    size: $0.size,
                    modificationDate: $0.dateModified,
                )
            },
            embeddings: Dictionary(uniqueKeysWithValues: snapshot.embeddings.compactMap { oldID, artifact in
                idMap[oldID].map { ($0, artifact) }
            }),
            sharpnessScores: Dictionary(
                uniqueKeysWithValues: snapshot.sharpnessScores.compactMap { oldID, score in
                    idMap[oldID].map { ($0, score) }
                },
            ),
            saliencyInfo: Dictionary(uniqueKeysWithValues: snapshot.saliencyInfo.compactMap { oldID, info in
                idMap[oldID].map { ($0, info) }
            }),
            groups: groups,
            boundaryEvidence: evidence,
            results: results,
            reviewStateSnapshots: snapshot.reviewStateSnapshots,
            similarityArtifactSetDigest: snapshot.similarityArtifactSetDigest,
        )
    }
}
