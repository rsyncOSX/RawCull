import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("Per-file analysis artifact store")
struct PerFileAnalysisArtifactStoreTests {
    @Test
    func `CLIP and Vision artifacts round-trip independently`() async throws {
        let fixture = try ArtifactStoreFixture()
        defer { fixture.remove() }
        let clipSource = try fixture.source(named: "clip.raw")
        let visionSource = try fixture.source(named: "vision.raw")
        let clipArtifact = fixture.artifact(
            source: clipSource,
            backend: fixture.clipBackend,
            dimensions: 3,
            payload: Data([1, 2, 3]),
        )
        let visionArtifact = fixture.artifact(
            source: visionSource,
            backend: fixture.visionBackend,
            dimensions: nil,
            payload: Data([4, 5, 6]),
        )

        let commit = await fixture.store.upsert(
            artifacts: [
                clipSource.id: clipArtifact,
                visionSource.id: visionArtifact
            ],
            sources: [
                clipSource.id: clipSource,
                visionSource.id: visionSource
            ],
            pipeline: fixture.pipeline,
        )
        let loaded = await fixture.store.load(
            sources: [clipSource, visionSource],
            allowedBackends: [fixture.clipBackend, fixture.visionBackend],
            pipeline: fixture.pipeline,
        )

        #expect(commit.failures.isEmpty)
        #expect(commit.committedSourceIDs == [clipSource.id, visionSource.id])
        #expect(loaded.artifacts[clipSource.id] == clipArtifact)
        #expect(loaded.artifacts[visionSource.id] == visionArtifact)
        #expect(loaded.misses.isEmpty)
    }

    @Test
    func `Source, backend, preview size, and pipeline changes are cache misses`() async throws {
        let fixture = try ArtifactStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source(named: "identity.raw")
        let artifact = fixture.artifact(
            source: source,
            backend: fixture.clipBackend,
            dimensions: 2,
            payload: Data([1, 2]),
        )
        _ = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )

        let wrongBackend = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.visionBackend],
            pipeline: fixture.pipeline,
        )
        let descriptorVariants = [
            SimilarityBackendDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: "different-model",
                representation: fixture.clipBackend.representation,
                preprocessingVersion: fixture.clipBackend.preprocessingVersion,
                normalizationVersion: fixture.clipBackend.normalizationVersion,
                configurationVersion: fixture.clipBackend.configurationVersion,
            ),
            SimilarityBackendDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: fixture.clipBackend.modelFingerprint,
                representation: "different-representation",
                preprocessingVersion: fixture.clipBackend.preprocessingVersion,
                normalizationVersion: fixture.clipBackend.normalizationVersion,
                configurationVersion: fixture.clipBackend.configurationVersion,
            ),
            SimilarityBackendDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: fixture.clipBackend.modelFingerprint,
                representation: fixture.clipBackend.representation,
                preprocessingVersion: "different-preprocessing",
                normalizationVersion: fixture.clipBackend.normalizationVersion,
                configurationVersion: fixture.clipBackend.configurationVersion,
            ),
            SimilarityBackendDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: fixture.clipBackend.modelFingerprint,
                representation: fixture.clipBackend.representation,
                preprocessingVersion: fixture.clipBackend.preprocessingVersion,
                normalizationVersion: "different-normalization",
                configurationVersion: fixture.clipBackend.configurationVersion,
            ),
            SimilarityBackendDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: fixture.clipBackend.modelFingerprint,
                representation: fixture.clipBackend.representation,
                preprocessingVersion: fixture.clipBackend.preprocessingVersion,
                normalizationVersion: fixture.clipBackend.normalizationVersion,
                configurationVersion: "different-configuration",
            )
        ]
        for descriptor in descriptorVariants {
            let mismatch = await fixture.store.load(
                sources: [source],
                allowedBackends: [descriptor],
                pipeline: fixture.pipeline,
            )
            #expect(mismatch.artifacts.isEmpty)
        }
        let wrongPreviewSize = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.clipBackend],
            pipeline: SimilarityArtifactPipelineSignature(
                thumbnailMaxPixelSize: fixture.pipeline.thumbnailMaxPixelSize + 1,
                pipelineVersion: fixture.pipeline.pipelineVersion,
            ),
        )
        let wrongPipeline = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.clipBackend],
            pipeline: SimilarityArtifactPipelineSignature(
                thumbnailMaxPixelSize: fixture.pipeline.thumbnailMaxPixelSize,
                pipelineVersion: fixture.pipeline.pipelineVersion + 1,
            ),
        )

        try Data([9, 9, 9]).write(to: source.url)
        let changedSource = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.clipBackend],
            pipeline: fixture.pipeline,
        )

        #expect(wrongBackend.artifacts.isEmpty)
        #expect(wrongPreviewSize.artifacts.isEmpty)
        #expect(wrongPipeline.artifacts.isEmpty)
        #expect(changedSource.artifacts.isEmpty)

        let staleSchemaArtifact = SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: fixture.clipBackend.backend,
                modelFingerprint: fixture.clipBackend.modelFingerprint,
                dimensions: 2,
                representation: fixture.clipBackend.representation,
                preprocessingVersion: fixture.clipBackend.preprocessingVersion,
                normalizationVersion: fixture.clipBackend.normalizationVersion,
                configurationVersion: fixture.clipBackend.configurationVersion,
                sourceFingerprint: SourceFingerprint(source: source),
                schemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion - 1,
            ),
            payload: Data([1, 2]),
        )
        let staleSchemaCommit = await fixture.store.upsert(
            artifacts: [source.id: staleSchemaArtifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        #expect(staleSchemaCommit.committedSourceIDs.isEmpty)
        #expect(staleSchemaCommit.failures.count == 1)
    }

    @Test
    func `A corrupt record is isolated from valid records`() async throws {
        let fixture = try ArtifactStoreFixture()
        defer { fixture.remove() }
        let first = try fixture.source(named: "first.raw")
        let second = try fixture.source(named: "second.raw")

        _ = await fixture.store.upsert(
            artifacts: [
                first.id: fixture.artifact(
                    source: first,
                    backend: fixture.clipBackend,
                    dimensions: 1,
                    payload: Data([1]),
                )
            ],
            sources: [first.id: first],
            pipeline: fixture.pipeline,
        )
        let firstRecord = try #require(fixture.recordURLs().first)

        _ = await fixture.store.upsert(
            artifacts: [
                second.id: fixture.artifact(
                    source: second,
                    backend: fixture.clipBackend,
                    dimensions: 1,
                    payload: Data([2]),
                )
            ],
            sources: [second.id: second],
            pipeline: fixture.pipeline,
        )
        try Data("truncated".utf8).write(to: firstRecord, options: .atomic)

        let loaded = await fixture.store.load(
            sources: [first, second],
            allowedBackends: [fixture.clipBackend],
            pipeline: fixture.pipeline,
        )

        #expect(loaded.artifacts[first.id] == nil)
        #expect(loaded.artifacts[second.id] != nil)
        #expect(loaded.misses == [
            PerFileAnalysisArtifactCacheMiss(
                sourceID: first.id,
                reason: .corrupt,
            )
        ])
        #expect(fixture.recordURLs().count == 1)
    }

    @Test
    func `Usage, pruning, and clear operate on individual records`() async throws {
        let fixture = try ArtifactStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source(named: "maintenance.raw")
        let artifact = fixture.artifact(
            source: source,
            backend: fixture.clipBackend,
            dimensions: 1,
            payload: Data([1]),
        )
        _ = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )

        let usageBeforePrune = await fixture.store.usage()
        let prune = await fixture.store.prune(
            policy: PerFileAnalysisArtifactPruningPolicy(
                maximumUnusedAge: .zero,
                maximumEntryCount: 50000,
            ),
            now: Date().addingTimeInterval(1),
        )
        let usageAfterPrune = await fixture.store.usage()

        #expect(usageBeforePrune.entryCount == 1)
        #expect(usageBeforePrune.size > 0)
        #expect(prune.removedEntryCount == 1)
        #expect(usageAfterPrune == PerFileAnalysisArtifactStoreUsage(
            size: 0,
            entryCount: 0,
        ))

        _ = await fixture.store.upsert(
            artifacts: [source.id: artifact],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        await fixture.store.clear()
        #expect(await fixture.store.usage().entryCount == 0)
    }

    @Test
    func `Replacement is atomic and cancellation preserves completed records`() async throws {
        let fixture = try ArtifactStoreFixture()
        defer { fixture.remove() }
        let source = try fixture.source(named: "replacement.raw")
        let original = fixture.artifact(
            source: source,
            backend: fixture.clipBackend,
            dimensions: 1,
            payload: Data([1]),
        )
        let replacement = fixture.artifact(
            source: source,
            backend: fixture.clipBackend,
            dimensions: 1,
            payload: Data([2]),
        )
        _ = await fixture.store.upsert(
            artifacts: [source.id: original],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        _ = await fixture.store.upsert(
            artifacts: [source.id: replacement],
            sources: [source.id: source],
            pipeline: fixture.pipeline,
        )
        let replaced = await fixture.store.load(
            sources: [source],
            allowedBackends: [fixture.clipBackend],
            pipeline: fixture.pipeline,
        )

        #expect(replaced.artifacts[source.id] == replacement)
        #expect(fixture.recordURLs().count == 1)

        var cancellationSources: [UUID: AIImageSource] = [:]
        var cancellationArtifacts: [UUID: SimilarityArtifact] = [:]
        for index in 0 ..< 32 {
            let item = try fixture.source(named: "cancel-\(index).raw")
            cancellationSources[item.id] = item
            cancellationArtifacts[item.id] = fixture.artifact(
                source: item,
                backend: fixture.clipBackend,
                dimensions: 1,
                payload: Data([UInt8(index)]),
            )
        }
        let gate = ArtifactStoreCancellationGate()
        let sourcesToCancel = cancellationSources
        let artifactsToCancel = cancellationArtifacts
        let store = fixture.store
        let pipeline = fixture.pipeline
        let cancelledWrite = Task.detached { @concurrent in
            await gate.wait()
            return await store.upsert(
                artifacts: artifactsToCancel,
                sources: sourcesToCancel,
                pipeline: pipeline,
            )
        }
        await gate.waitUntilStarted()
        cancelledWrite.cancel()
        await gate.release()
        let cancelledResult = await cancelledWrite.value
        let loadedAfterCancellation = await fixture.store.load(
            sources: Array(cancellationSources.values),
            allowedBackends: [fixture.clipBackend],
            pipeline: fixture.pipeline,
        )

        #expect(cancelledResult.wasCancelled)
        #expect(cancelledResult.failures.isEmpty)
        #expect(
            loadedAfterCancellation.artifacts.count
                == cancelledResult.committedSourceIDs.count,
        )
        #expect(loadedAfterCancellation.misses.allSatisfy { $0.reason == .notFound })
        #expect(replaced.artifacts[source.id] == replacement)
    }

    @Test
    func `Cancellation during persistence retains only completed records`() async throws {
        let gate = ArtifactStorePartialCommitGate()
        let fixture = try ArtifactStoreFixture { _, committedSourceIDs in
            await gate.pauseAfterFirstCommit(committedSourceIDs)
        }
        defer { fixture.remove() }

        var sources: [UUID: AIImageSource] = [:]
        var artifacts: [UUID: SimilarityArtifact] = [:]
        for index in 0 ..< 3 {
            let source = try fixture.source(named: "partial-\(index).raw")
            sources[source.id] = source
            artifacts[source.id] = fixture.artifact(
                source: source,
                backend: fixture.clipBackend,
                dimensions: 1,
                payload: Data([UInt8(index)]),
            )
        }

        let store = fixture.store
        let pipeline = fixture.pipeline
        let sourcesToCommit = sources
        let artifactsToCommit = artifacts
        let commit = Task.detached { @concurrent in
            await store.upsert(
                artifacts: artifactsToCommit,
                sources: sourcesToCommit,
                pipeline: pipeline,
            )
        }
        await gate.waitUntilPaused()
        commit.cancel()
        await gate.release()
        let result = await commit.value
        let loaded = await store.load(
            sources: Array(sourcesToCommit.values),
            allowedBackends: [fixture.clipBackend],
            pipeline: pipeline,
        )

        #expect(result.wasCancelled)
        #expect(result.committedSourceIDs.count == 1)
        #expect(result.failures.isEmpty)
        #expect(Set(loaded.artifacts.keys) == result.committedSourceIDs)
        #expect(loaded.misses.count == 2)
    }
}

private actor ArtifactStoreCancellationGate {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ArtifactStorePartialCommitGate {
    private var isPaused = false
    private var continuation: CheckedContinuation<Void, Never>?

    func pauseAfterFirstCommit(_ committedSourceIDs: Set<UUID>) async {
        guard committedSourceIDs.count == 1 else { return }
        isPaused = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilPaused() async {
        while !isPaused {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private nonisolated struct ArtifactStoreFixture: Sendable {
    let root: URL
    let store: PerFileAnalysisArtifactStore
    let pipeline = SimilarityArtifactPipelineSignature(
        thumbnailMaxPixelSize: 512,
        pipelineVersion: 3,
    )
    let clipBackend = SimilarityBackendDescriptor(
        backend: "clip",
        modelFingerprint: "clip-test-model",
        representation: "normalized-float-vector-json-v1",
        preprocessingVersion: "preview-v1",
        normalizationVersion: "l2-v1",
        configurationVersion: "config-v1",
    )
    let visionBackend = SimilarityBackendDescriptor(
        backend: "vision-feature-print",
        modelFingerprint: "vision-test-model",
        representation: "vnfeatureprint-keyed-archive-v1",
        preprocessingVersion: "vision-v1",
        normalizationVersion: "native-v1",
        configurationVersion: "revision-2",
    )

    init(
        writeBarrier: PerFileAnalysisArtifactWriteBarrier? = nil,
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "PerFileAnalysisArtifactStoreTests-\(UUID().uuidString)",
                isDirectory: true,
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
        )
        store = PerFileAnalysisArtifactStore(
            storageDirectory: root.appendingPathComponent("store", isDirectory: true),
            writeBarrier: writeBarrier,
        )
    }

    func source(named name: String) throws -> AIImageSource {
        let url = root.appendingPathComponent(name)
        try Data(name.utf8).write(to: url, options: .atomic)
        return AIImageSource(
            id: UUID(),
            url: url,
            displayName: name,
        )
    }

    func artifact(
        source: AIImageSource,
        backend: SimilarityBackendDescriptor,
        dimensions: Int?,
        payload: Data,
    ) -> SimilarityArtifact {
        SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backend,
                dimensions: dimensions,
                sourceFingerprint: SourceFingerprint(source: source),
            ),
            payload: payload,
        )
    }

    func recordURLs() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: store.storageDirectory,
            includingPropertiesForKeys: nil,
        )) ?? []
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
