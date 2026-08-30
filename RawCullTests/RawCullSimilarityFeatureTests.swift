import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

private nonisolated let featureTestBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "feature-test-v1",
    representation: "feature-test-representation",
    preprocessingVersion: "feature-test-preprocessing-v1",
    normalizationVersion: "feature-test-normalization-v1",
    configurationVersion: "feature-test-configuration-v1",
)

@Suite("RawCull similarity feature", .tags(.smoke))
@MainActor
struct RawCullSimilarityFeatureTests {
    @Test
    func `Feature and semantic search share the exact model and feature`() {
        let model = makeModel()
        let feature = RawCullSimilarityFeature(similarityModel: model)
        let semantic = RawCullSemanticSearchFeature(
            similarityModel: model,
            similarityFeature: feature,
        )

        #expect(feature.sharesSimilarityModelIdentity(with: model))
        #expect(semantic.sharesSimilarityModelIdentity(with: model))
        #expect(semantic.sharesSimilarityFeatureIdentity(with: feature))
    }

    @Test
    func `Presentation hides backend descriptors and model progress`() {
        let model = makeModel(service: FeatureTestSimilarityService())
        let feature = RawCullSimilarityFeature(similarityModel: model)
        model.isIndexing = true
        model.indexingProgress = 3
        model.indexingTotal = 8
        model.indexingEstimatedSeconds = 5

        #expect(feature.backend.kind == .clip)
        #expect(feature.backend.displayName == "CLIP")
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
    func `Backend replacement resets burst state before replacing the model service`() {
        let model = makeModel()
        let feature = RawCullSimilarityFeature(similarityModel: model)
        var descriptorObservedDuringReset: SimilarityBackendDescriptor?
        let context = FeatureTestApplicationContext {
            descriptorObservedDuringReset = model.backendDescriptor
        }
        feature.bindApplicationContext(context)
        let previousDescriptor = model.backendDescriptor

        feature.replaceSimilarityService(FeatureTestSimilarityService())

        #expect(context.burstResetCount == 1)
        #expect(descriptorObservedDuringReset == previousDescriptor)
        #expect(model.backendDescriptor == featureTestBackend)
        #expect(feature.imageHydrationTask == nil)
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
    private(set) var burstResetCount = 0
    private let onBurstReset: () -> Void

    init(onBurstReset: @escaping () -> Void = {}) {
        self.onBurstReset = onBurstReset
    }

    func cancelAndResetBurstAnalysisForSimilarityBackendChange() {
        burstResetCount += 1
        onBurstReset()
    }
}
