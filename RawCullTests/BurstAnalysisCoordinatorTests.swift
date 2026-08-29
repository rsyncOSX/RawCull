import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

@MainActor
@Suite(.tags(.smoke))
struct BurstAnalysisCoordinatorTests {
    @Test
    func `compatible cache hit returns remapped snapshot and review state`() async throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw"), makeCoordinatorFile("B.raw")]
        let group = BurstGroup(id: 7, fileIDs: files.map(\.id))
        let signature = try #require(BurstGroupSignature(files: files, catalog: catalog))
        let (coordinator, repository, request) = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        repository.snapshot = makeCoordinatorSnapshot(
            request: request,
            groups: [group],
            reviewStates: [BurstReviewStateSnapshot(signature: signature, state: .reviewed)],
        )

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .hit)
        #expect(result?.compatibleSnapshot?.groups == [group])
        #expect(result?.restoredReviewStates == [group.id: .reviewed])
        #expect(repository.loadCount == 1)
        #expect(repository.migrationLoadCount == 0)
    }

    @Test
    func `artifact digest mismatch rejects derived cache`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw")]
        let (coordinator, repository, request) = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        var snapshot = makeCoordinatorSnapshot(request: request)
        snapshot.similarityArtifactSetDigest = "different-artifact-set"
        repository.snapshot = snapshot

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .rejectedArtifactSet)
        #expect(result?.compatibleSnapshot == nil)
    }

    @Test
    func `legacy candidate is remapped before import decision`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let currentFiles = [makeCoordinatorFile("A.raw"), makeCoordinatorFile("B.raw")]
        let oldFiles = currentFiles.map { file in
            FileItem(
                url: file.url,
                name: file.name,
                size: file.size,
                dateModified: file.dateModified,
                captureDate: file.captureDate,
                exifData: nil,
                afFocusNormalized: nil,
            )
        }
        let oldGroup = BurstGroup(id: 3, fileIDs: oldFiles.map(\.id))
        let (coordinator, repository, request) = makeCoordinatorHarness(
            catalog: catalog,
            files: currentFiles,
        )
        repository.migrationCandidate = makeCoordinatorSnapshot(
            request: request,
            files: oldFiles,
            groups: [oldGroup],
        )

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: true,
            isCurrent: { true },
        )

        #expect(result?.cacheOutcome == .miss)
        #expect(result?.diagnostics == [.legacyMigrationCandidateFound])
        #expect(result?.migrationCandidate?.files.map(\.id) == currentFiles.map(\.id))
        #expect(result?.migrationCandidate?.groups.first?.fileIDs == currentFiles.map(\.id))
        #expect(repository.migrationLoadCount == 1)
    }

    @Test
    func `superseded cache preparation returns no result`() async {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCoordinatorFile("A.raw")]
        let (coordinator, repository, request) = makeCoordinatorHarness(
            catalog: catalog,
            files: files,
        )
        repository.snapshot = makeCoordinatorSnapshot(request: request)
        repository.invalidateOnLoad = true

        let result = await coordinator.prepareCache(
            for: request,
            importLegacyCandidate: false,
            isCurrent: { repository.isValid },
        )

        #expect(result == nil)
        #expect(repository.loadCount == 1)
    }

    @Test
    func `review restoration follows membership rather than group id`() throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCoordinatorFile("A.raw")
        let second = makeCoordinatorFile("B.raw")
        let third = makeCoordinatorFile("C.raw")
        let signature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )

        let restored = BurstAnalysisCoordinator.restoredReviewStates(
            snapshots: [BurstReviewStateSnapshot(signature: signature, state: .deferred)],
            groups: [
                BurstGroup(id: 1, fileIDs: [first.id, third.id]),
                BurstGroup(id: 9, fileIDs: [first.id, second.id]),
            ],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored == [9: .deferred])
    }
}

@MainActor
private final class CoordinatorCacheRepository: BurstAnalysisCacheRepository {
    var snapshot: BurstAnalysisCacheSnapshot?
    var migrationCandidate: BurstAnalysisCacheSnapshot?
    var invalidateOnLoad = false
    var isValid = true
    private(set) var loadCount = 0
    private(set) var migrationLoadCount = 0

    func load(
        catalog _: URL,
        files _: [FileItem],
        thumbnailMaxPixelSize _: Int,
        sharpnessSignature _: BurstSharpnessSignature,
        similaritySignature _: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        loadCount += 1
        if invalidateOnLoad {
            isValid = false
        }
        return snapshot
    }

    func loadMigrationCandidate(catalog _: URL) async -> BurstAnalysisCacheSnapshot? {
        migrationLoadCount += 1
        return migrationCandidate
    }

    func save(_: BurstAnalysisCacheSnapshot, catalog _: URL) async {}
    func delete(catalog _: URL) async {}
}

@MainActor
private func makeCoordinatorHarness(
    catalog: URL,
    files: [FileItem],
) -> (BurstAnalysisCoordinator, CoordinatorCacheRepository, BurstAnalysisPipelineRequest) {
    let model = SimilarityScoringModel(
        artifactStore: makeIsolatedSimilarityArtifactStore(),
    )
    let feature = RawCullSimilarityFeature(similarityModel: model)
    let repository = CoordinatorCacheRepository()
    let coordinator = BurstAnalysisCoordinator(
        similarityFeature: feature,
        similarityModel: model,
        cacheRepository: repository,
    )
    let similaritySignature = BurstSimilaritySignature(
        groupingConfig: BurstGroupingConfig(),
        backendDescriptor: model.backendDescriptor,
        artifactBackendDescriptors: model.artifactBackendDescriptors,
        artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
        embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
    )
    let sharpnessModel = SharpnessScoringModel()
    let request = BurstAnalysisPipelineRequest(
        catalogIdentity: catalog,
        orderedFiles: files,
        sharpnessSignature: sharpnessModel.scoringSignature,
        similaritySignature: similaritySignature,
        generation: 1,
        configuration: BurstAnalysisPipelineConfiguration(
            thumbnailMaxPixelSize: sharpnessModel.effectiveThumbnailMaxPixelSize,
            grouping: similaritySignature.groupingConfig,
            cacheSchemaVersion: BurstAnalysisCache.schemaVersion,
            groupingAlgorithmVersion: BurstGroupingConfig.algorithmVersion,
        ),
    )
    return (coordinator, repository, request)
}

private nonisolated func makeCoordinatorFile(_ name: String) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 1),
        captureDate: Date(timeIntervalSince1970: 1),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

@MainActor
private func makeCoordinatorSnapshot(
    request: BurstAnalysisPipelineRequest,
    files: [FileItem]? = nil,
    groups: [BurstGroup] = [],
    reviewStates: [BurstReviewStateSnapshot] = [],
) -> BurstAnalysisCacheSnapshot {
    let files = files ?? request.orderedFiles
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
        embeddings: [:],
        sharpnessScores: [:],
        saliencyInfo: [:],
        groups: groups,
        boundaryEvidence: [],
        results: [],
        reviewStateSnapshots: reviewStates,
        similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
            files: request.orderedFiles,
            artifacts: [:],
        ),
    )
}
