import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore

@MainActor
final class CoordinatorCacheRepository: BurstAnalysisCacheRepository {
    var snapshot: BurstAnalysisCacheSnapshot?
    var migrationCandidate: BurstAnalysisCacheSnapshot?
    var invalidateOnLoad = false
    var isValid = true
    private(set) var loadCount = 0
    private(set) var migrationLoadCount = 0
    private(set) var savedSnapshots: [BurstAnalysisCacheSnapshot] = []

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

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog _: URL) async {
        savedSnapshots.append(snapshot)
    }

    func delete(catalog _: URL) async {}
}

@MainActor
struct CoordinatorComputeHarness {
    let coordinator: BurstAnalysisCoordinator
    let repository: CoordinatorCacheRepository
    let request: BurstAnalysisPipelineRequest
    let sharpnessModel: SharpnessScoringModel
}

@MainActor
func makeCoordinatorComputeHarness(
    catalog: URL,
    files: [FileItem],
) -> CoordinatorComputeHarness {
    makeCoordinatorHarness(catalog: catalog, files: files)
}

@MainActor
func makeCoordinatorHarness(
    catalog: URL,
    files: [FileItem],
) -> CoordinatorComputeHarness {
    let model = SimilarityScoringModel(
        artifactStore: makeIsolatedSimilarityArtifactStore(),
    )
    let feature = RawCullSimilarityFeature(similarityModel: model)
    let repository = CoordinatorCacheRepository()
    let sharpnessModel = SharpnessScoringModel()
    let coordinator = BurstAnalysisCoordinator(
        sharpnessModel: sharpnessModel,
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
    return CoordinatorComputeHarness(
        coordinator: coordinator,
        repository: repository,
        request: request,
        sharpnessModel: sharpnessModel,
    )
}

nonisolated func makeCoordinatorFile(_ name: String) -> FileItem {
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

nonisolated func makeCoordinatorArtifact(
    file: FileItem,
    backend: SimilarityBackendDescriptor,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: backend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(
                standardizedPath: file.url.standardizedFileURL.path,
                fileSize: file.size,
                modificationDate: file.dateModified,
            ),
        ),
        payload: Data([0]),
    )
}

@MainActor
func makeCoordinatorSnapshot(
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
