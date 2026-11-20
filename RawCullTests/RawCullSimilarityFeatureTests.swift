import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
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

    @Test(.timeLimit(.minutes(1)))
    func `Cancelled grouping publishes no partial groups`() async throws {
        let gate = BlockingDistanceGate(blockAtCall: 70)
        let model = makeModel(service: BlockingDistanceService(gate: gate))
        let files = (0 ..< 200).map { makeCoordinatorFile("G\($0).raw") }
        model.embeddings = Dictionary(uniqueKeysWithValues: files.map {
            ($0.id, makeCoordinatorArtifact(file: $0, backend: featureTestBackend))
        })

        let task = Task { await model.groupBursts(files: files) }
        while !gate.hasBlocked {
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        gate.release()
        await task.value

        #expect(model.burstGroups.isEmpty)
        #expect(model.burstBoundaryEvidence.isEmpty)
        #expect(!model.isGrouping)

        // An uncancelled run over the same files yields the single burst.
        await model.groupBursts(files: files)
        #expect(model.burstGroups.map(\.fileIDs) == [files.map(\.id)])
    }

    @Test(.timeLimit(.minutes(1)))
    func `Superseded indexing request still returns with its files indexed`() async throws {
        let gate = SequencedIndexGate()
        let model = makeModel(service: SequencedIndexService(gate: gate))
        let catalog = (0 ..< 6).map { makeCoordinatorFile("I\($0).raw") }
        let burstFiles = Array(catalog.prefix(3))

        let burst = Task { () -> Bool in
            await model.indexFiles(burstFiles)
            return model.hasCompleteSimilarityIndex(for: burstFiles)
        }
        try await gate.waitForCalls(1)
        // The user starts Index Similarity for the whole catalog meanwhile.
        let full = Task { await model.indexFiles(catalog) }
        try await gate.waitForCalls(2)
        // The superseded burst request finishes first; the catalog request
        // is still running when the burst caller resumes.
        await gate.release(call: 1)
        try await Task.sleep(for: .milliseconds(50))
        await gate.release(call: 2)

        #expect(await burst.value)
        await full.value
        #expect(model.hasCompleteSimilarityIndex(for: catalog))
        #expect(!model.isIndexing)
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

/// Blocks the `blockAtCall`-th distance call until released, once.
private nonisolated final class BlockingDistanceGate: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private let blockAtCall: Int
    private var calls = 0
    private var blocked = false

    init(blockAtCall: Int) {
        self.blockAtCall = blockAtCall
    }

    var hasBlocked: Bool {
        lock.withLock { blocked }
    }

    func recordCall() {
        let shouldBlock = lock.withLock {
            calls += 1
            guard calls == blockAtCall else { return false }
            blocked = true
            return true
        }
        if shouldBlock {
            semaphore.wait()
        }
    }

    func release() {
        semaphore.signal()
    }
}

private nonisolated struct BlockingDistanceService: RawCullSimilarityServicing {
    let backendDescriptor = featureTestBackend
    let gate: BlockingDistanceGate

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
        gate.recordCall()
        return 0.01
    }
}

private actor SequencedIndexGate {
    private var calls = 0
    private var released: Set<Int> = []
    private var waiters: [Int: CheckedContinuation<Void, Never>] = [:]

    func enter() async {
        calls += 1
        let call = calls
        guard !released.contains(call) else { return }
        await withCheckedContinuation { waiters[call] = $0 }
    }

    func waitForCalls(_ count: Int) async throws {
        while calls < count {
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    func release(call: Int) {
        released.insert(call)
        waiters.removeValue(forKey: call)?.resume()
    }
}

/// Each `index` call waits for its own release, then indexes every source.
private nonisolated struct SequencedIndexService: RawCullSimilarityServicing {
    let backendDescriptor = featureTestBackend
    let gate: SequencedIndexGate

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress _: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        await gate.enter()
        let artifacts = Dictionary(uniqueKeysWithValues: sources.map { source in
            (
                source.id,
                SimilarityArtifact(
                    descriptor: SimilarityArtifactDescriptor(
                        backend: backendDescriptor,
                        dimensions: 1,
                        sourceFingerprint: SourceFingerprint(source: source),
                    ),
                    payload: Data([0]),
                ),
            )
        })
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: [])
    }

    func distance(from _: SimilarityArtifact, to _: SimilarityArtifact) throws -> Float? {
        0.01
    }
}
