import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

private nonisolated let matrixDataCompBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "datacomp-test",
    representation: "matrix-vector-v1",
    preprocessingVersion: "datacomp-v1",
    normalizationVersion: "l2-v1",
    configurationVersion: "matrix-v1",
)

private nonisolated let matrixOpenAIBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "openai-test",
    representation: "matrix-vector-v1",
    preprocessingVersion: "openai-v1",
    normalizationVersion: "l2-v1",
    configurationVersion: "matrix-v1",
)

private nonisolated let matrixVisionBackend = SimilarityBackendDescriptor(
    backend: "vision-feature-print",
    modelFingerprint: "vision-test",
    representation: "matrix-vector-v1",
    preprocessingVersion: "vision-v1",
    normalizationVersion: "native-v1",
    configurationVersion: "revision-2",
)

@MainActor
@Suite("Typed AI persistence matrix", .tags(.smoke))
struct TypedAIPersistenceMatrixTests {
    private let pipeline = SimilarityScoringModel.artifactPipelineSignature

    @Test
    func `dataComp and OpenAI artifacts relaunch without cross-loading`() async throws {
        let root = try makeMatrixRoot("backend-relaunch")
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("store", isDirectory: true)
        let source = try makeMatrixSource(root: root, name: "shared.raw", bytes: [1])
        let dataComp = matrixArtifact(source: source, backend: matrixDataCompBackend, value: 1)
        let openAI = matrixArtifact(source: source, backend: matrixOpenAIBackend, value: 2)
        let initialStore = PerFileAnalysisArtifactStore(storageDirectory: storeURL)

        _ = await initialStore.upsert(
            artifacts: [source.id: dataComp],
            sources: [source.id: source],
            pipeline: pipeline,
        )
        _ = await initialStore.upsert(
            artifacts: [source.id: openAI],
            sources: [source.id: source],
            pipeline: pipeline,
        )

        let relaunchedStore = PerFileAnalysisArtifactStore(storageDirectory: storeURL)
        let reloadedDataComp = await relaunchedStore.load(
            sources: [source],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )
        let reloadedOpenAI = await relaunchedStore.load(
            sources: [source],
            allowedBackends: [matrixOpenAIBackend],
            pipeline: pipeline,
        )
        let wrongDecoder = await relaunchedStore.load(
            sources: [source],
            allowedBackends: [matrixVisionBackend],
            pipeline: pipeline,
        )

        #expect(reloadedDataComp.artifacts[source.id] == dataComp)
        #expect(reloadedOpenAI.artifacts[source.id] == openAI)
        #expect(wrongDecoder.artifacts.isEmpty)
        #expect(await relaunchedStore.usage().entryCount == 2)
    }

    @Test
    func `source add replace rename and removal preserve only compatible active records`() async throws {
        let root = try makeMatrixRoot("source-mutations")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerFileAnalysisArtifactStore(
            storageDirectory: root.appendingPathComponent("store", isDirectory: true),
        )
        let original = try makeMatrixSource(root: root, name: "original.raw", bytes: [1])
        let survivor = try makeMatrixSource(root: root, name: "survivor.raw", bytes: [2])
        // swiftlint:disable trailing_comma
        let artifacts = [
            original.id: matrixArtifact(source: original, backend: matrixDataCompBackend, value: 1),
            survivor.id: matrixArtifact(source: survivor, backend: matrixDataCompBackend, value: 2),
        ]
        // swiftlint:enable trailing_comma
        _ = await store.upsert(
            artifacts: artifacts,
            sources: [original.id: original, survivor.id: survivor],
            pipeline: pipeline,
        )

        let added = try makeMatrixSource(root: root, name: "added.raw", bytes: [3])
        let afterAdd = await store.load(
            sources: [original, survivor, added],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )
        #expect(Set(afterAdd.artifacts.keys) == [original.id, survivor.id])
        #expect(afterAdd.misses.map(\.sourceID) == [added.id])

        try Data([9, 9, 9, 9]).write(to: original.url, options: .atomic)
        let replaced = AIImageSource(
            id: original.id,
            url: original.url,
            displayName: original.displayName,
        )
        let afterReplacement = await store.load(
            sources: [replaced, survivor],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )
        #expect(Set(afterReplacement.artifacts.keys) == [survivor.id])

        let renamedURL = root.appendingPathComponent("renamed.raw")
        try FileManager.default.moveItem(at: original.url, to: renamedURL)
        let renamed = AIImageSource(
            id: original.id,
            url: renamedURL,
            displayName: renamedURL.lastPathComponent,
        )
        let afterRename = await store.load(
            sources: [renamed, survivor],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )
        let afterRemoval = await store.load(
            sources: [survivor],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )

        #expect(Set(afterRename.artifacts.keys) == [survivor.id])
        #expect(Set(afterRemoval.artifacts.keys) == [survivor.id])
    }

    @Test
    func `superseded semantic hydration cannot publish an older backend`() async throws {
        let root = try makeMatrixRoot("semantic-hydration")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try makeMatrixFile(root: root, name: "semantic.raw", bytes: [1])
        let store = MatrixHydrationStore(suspendedBackend: matrixDataCompBackend)
        let oldService = MatrixSemanticService(backendDescriptor: matrixDataCompBackend)
        let newService = MatrixSemanticService(backendDescriptor: matrixOpenAIBackend)
        let model = SimilarityScoringModel(
            semanticSearchCapability: .ready(location: nil, backend: matrixDataCompBackend),
            semanticSearchService: oldService,
            artifactStore: store,
        )

        let oldHydration = Task {
            await model.hydrateSemanticArtifacts([file])
        }
        await store.waitUntilSuspended()
        model.setSemanticSearchCapability(
            .ready(location: nil, backend: matrixOpenAIBackend),
            service: newService,
        )
        let newCount = await model.hydrateSemanticArtifacts([file])
        await store.release()
        let oldCount = await oldHydration.value

        #expect(oldCount == 0)
        #expect(newCount == 1)
        #expect(model.semanticIndexedFileCount == 1)
        #expect(model.semanticSearchBackendDescriptor == matrixOpenAIBackend)
        #expect(model.semanticSearchState == .idle)
    }

    @Test
    func `a per-record write failure retains usable session artifacts and returns idle`() async throws {
        let root = try makeMatrixRoot("session-write-failure")
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("store", isDirectory: true)
        let store = PerFileAnalysisArtifactStore(storageDirectory: storeURL)
        let blockedFile = try makeMatrixFile(root: root, name: "blocked.raw", bytes: [1])
        let goodFile = try makeMatrixFile(root: root, name: "good.raw", bytes: [2])
        let blockedSource = SimilarityScoringModel.source(for: blockedFile)
        // swiftlint:disable trailing_comma
        _ = await store.upsert(
            artifacts: [
                blockedFile.id: matrixArtifact(
                    source: blockedSource,
                    backend: matrixDataCompBackend,
                    value: 1,
                ),
            ],
            sources: [blockedFile.id: blockedSource],
            pipeline: pipeline,
        )
        // swiftlint:enable trailing_comma
        let blockedRecord = try #require(
            FileManager.default.contentsOfDirectory(
                at: storeURL,
                includingPropertiesForKeys: nil,
            ).first,
        )
        try FileManager.default.removeItem(at: blockedRecord)
        try FileManager.default.createDirectory(at: blockedRecord, withIntermediateDirectories: true)

        let service = MatrixSimilarityService(
            backendDescriptor: matrixDataCompBackend,
            valuesByName: ["blocked.raw": 9, "good.raw": 7],
        )
        let model = SimilarityScoringModel(
            similarityService: service,
            artifactStore: store,
        )
        await model.indexFiles([blockedFile, goodFile], forceRefresh: true)

        #expect(model.embeddings[blockedFile.id]?.payload == Data([9]))
        #expect(model.embeddings[goodFile.id]?.payload == Data([7]))
        #expect(model.indexingPersistenceFailures.map(\.sourceID) == [blockedFile.id])
        #expect(model.indexingOperationFailure != nil)
        #expect(model.isIndexing == false)
        #expect(model.indexingPhase == .idle)
        #expect(model.indexingProgress == 0)

        let reloaded = await PerFileAnalysisArtifactStore(storageDirectory: storeURL).load(
            sources: [blockedSource, SimilarityScoringModel.source(for: goodFile)],
            allowedBackends: [matrixDataCompBackend],
            pipeline: pipeline,
        )
        #expect(Set(reloaded.artifacts.keys) == [goodFile.id])
    }
}

private actor MatrixHydrationStore: SimilarityArtifactStoring {
    private let suspendedBackend: SimilarityBackendDescriptor
    private var isSuspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(suspendedBackend: SimilarityBackendDescriptor) {
        self.suspendedBackend = suspendedBackend
    }

    func load(
        sources: [AIImageSource],
        allowedBackends: [SimilarityBackendDescriptor],
        pipeline _: SimilarityArtifactPipelineSignature,
    ) async -> PerFileAnalysisArtifactLoadResult {
        guard let backend = allowedBackends.first else {
            return PerFileAnalysisArtifactLoadResult(artifacts: [:], misses: [])
        }
        if backend == suspendedBackend {
            isSuspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return PerFileAnalysisArtifactLoadResult(
            artifacts: Dictionary(uniqueKeysWithValues: sources.map { source in
                (source.id, matrixArtifact(source: source, backend: backend, value: 1))
            }),
            misses: [],
        )
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

    func waitUntilSuspended() async {
        while !isSuspended {
            await Task.yield()
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private nonisolated struct MatrixSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor: SimilarityBackendDescriptor
    let valuesByName: [String: UInt8]

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        for (offset, source) in sources.enumerated() {
            artifacts[source.id] = matrixArtifact(
                source: source,
                backend: backendDescriptor,
                value: valuesByName[source.displayName] ?? 0,
            )
            await progress?(RawCullSimilarityIndexingProgress(
                completed: offset + 1,
                total: sources.count,
                currentSourceID: source.id,
            ))
        }
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: [])
    }

    func distance(from left: SimilarityArtifact, to right: SimilarityArtifact) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor) else { return nil }
        return 0
    }
}

private nonisolated struct MatrixSemanticService: RawCullSemanticSearchServicing {
    let backendDescriptor: SimilarityBackendDescriptor
    let promptPolicyVersion = "matrix-v1"

    func rank(
        query _: String,
        candidates _: [RawCullSemanticSearchCandidate],
    ) async throws -> RawCullSemanticSearchOutput {
        throw RawCullSemanticSearchError.noCompatibleArtifacts
    }
}

private nonisolated func matrixArtifact(
    source: AIImageSource,
    backend: SimilarityBackendDescriptor,
    value: UInt8,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: backend,
            dimensions: 1,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: Data([value]),
    )
}

private nonisolated func makeMatrixRoot(_ name: String) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("TypedAIPersistenceMatrixTests", isDirectory: true)
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private nonisolated func makeMatrixSource(
    root: URL,
    name: String,
    bytes: [UInt8],
    id: UUID = UUID(),
) throws -> AIImageSource {
    let url = root.appendingPathComponent(name)
    try Data(bytes).write(to: url, options: .atomic)
    return AIImageSource(id: id, url: url, displayName: name)
}

private nonisolated func makeMatrixFile(
    root: URL,
    name: String,
    bytes: [UInt8],
) throws -> FileItem {
    let source = try makeMatrixSource(root: root, name: name, bytes: bytes)
    let identity = SourceFileIdentity.read(from: source.url)
    return FileItem(
        id: source.id,
        url: source.url,
        name: source.displayName,
        size: identity.fileSize ?? 0,
        dateModified: identity.modificationDate ?? .distantPast,
        exifData: nil,
        afFocusNormalized: nil,
    )
}
