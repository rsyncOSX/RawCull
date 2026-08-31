import Foundation
@testable import RawCull
import Testing

private nonisolated let featureTestBackend = SimilarityBackendDescriptor(
    backend: "vision-feature-print",
    modelFingerprint: "feature-test-v1",
    representation: "feature-test-representation",
    preprocessingVersion: 1,
    normalizationVersion: 0,
    configurationVersion: 2,
)

@Suite("RawCull similarity feature", .tags(.smoke))
@MainActor
struct RawCullSimilarityFeatureTests {
    @Test
    func `Feature shares the exact similarity model`() {
        let model = makeModel()
        let feature = RawCullSimilarityFeature(similarityModel: model)

        #expect(feature.sharesSimilarityModelIdentity(with: model))
    }

    @Test
    func `Presentation hides backend descriptors and model progress`() {
        let model = makeModel(service: FeatureTestSimilarityService())
        let feature = RawCullSimilarityFeature(similarityModel: model)
        model.isIndexing = true
        model.indexingProgress = 3
        model.indexingTotal = 8
        model.indexingEstimatedSeconds = 5

        #expect(feature.backend.kind == .vision)
        #expect(feature.backend.displayName == "Vision")
        #expect(
            feature.indexing == RawCullSimilarityIndexingPresentation(
                isIndexing: true,
                phase: .idle,
                completed: 3,
                total: 8,
                estimatedSeconds: 5,
                generationFailureCount: 0,
                persistenceFailureCount: 0,
                operationFailure: nil,
            ),
        )
    }

    @Test
    func `Catalog hydration rejects a stale catalog identity`() async {
        let model = makeModel()
        let feature = RawCullSimilarityFeature(similarityModel: model)
        let context = FeatureTestApplicationContext()
        context.currentSimilarityCatalogSnapshot = RawCullSimilarityCatalogSnapshot(
            files: [],
            identity: RawCullSimilarityCatalogIdentity(
                catalogURL: URL(fileURLWithPath: "/tmp/new-catalog"),
                generation: 2,
            ),
        )
        feature.bindApplicationContext(context)

        let accepted = await feature.hydrateCatalog(
            RawCullSimilarityCatalogHydrationRequest(
                files: [],
                catalogIdentity: RawCullSimilarityCatalogIdentity(
                    catalogURL: URL(fileURLWithPath: "/tmp/old-catalog"),
                    generation: 1,
                ),
            ),
        )

        #expect(!accepted)
        #expect(feature.catalogHydrationTask == nil)
    }

    private func makeModel(
        service: any RawCullSimilarityServicing = RawCullVisionSimilarityService(),
    ) -> SimilarityScoringModel {
        SimilarityScoringModel(
            similarityService: service,
            artifactStore: FeatureTestArtifactStore(),
        )
    }
}

private nonisolated struct FeatureTestSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = featureTestBackend

    func index(
        sources _: [AIImageSource],
        maxPixelSize _: Int,
        progress _: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        RawCullSimilarityIndexingOutput(artifacts: [:], failures: [])
    }

    func distance(
        from _: SimilarityArtifact,
        to _: SimilarityArtifact,
    ) throws -> Float? {
        nil
    }
}

private actor FeatureTestArtifactStore: SimilarityArtifactStoring {
    func load(
        sources _: [AIImageSource],
        allowedBackends _: [SimilarityBackendDescriptor],
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactLoadResult {
        PerFileAnalysisArtifactLoadResult(artifacts: [:], misses: [])
    }

    func upsert(
        artifacts _: [UUID: SimilarityArtifact],
        sources _: [UUID: AIImageSource],
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactCommitResult {
        PerFileAnalysisArtifactCommitResult(
            committedSourceIDs: [],
            failures: [],
            wasCancelled: false,
        )
    }

    func remove(
        source _: AIImageSource,
        backend _: SimilarityBackendDescriptor,
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async {}
}

@MainActor
private final class FeatureTestApplicationContext: RawCullSimilarityApplicationContext {
    var currentSimilarityCatalogSnapshot = RawCullSimilarityCatalogSnapshot(
        files: [],
        identity: RawCullSimilarityCatalogIdentity(
            catalogURL: nil,
            generation: 0,
        ),
    )
}
