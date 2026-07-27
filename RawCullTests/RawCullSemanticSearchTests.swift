import Foundation
import PhotoAIContracts
@testable import RawCull
import RawCullCore
import Testing

private nonisolated let semanticTestBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "semantic-test-model-v1",
    representation: "float32-l2-normalized",
    preprocessingVersion: "semantic-test-preprocess-v1",
    normalizationVersion: "semantic-test-normalization-v1",
    configurationVersion: "semantic-test-config-v1",
)

private nonisolated let visionOnlyTestBackend = SimilarityBackendDescriptor(
    backend: "vision-feature-print",
    modelFingerprint: "vision-test-model-v1",
    representation: "vision-feature-print",
    preprocessingVersion: "vision-test-preprocess-v1",
    normalizationVersion: "vision-test-normalization-v1",
    configurationVersion: "vision-test-config-v1",
)

private nonisolated let semanticTestTextDescriptor = TextEmbeddingDescriptor(
    backend: semanticTestBackend,
    dimensions: 2,
    tokenizerVersion: "semantic-test-tokenizer-v1",
)

private enum SemanticTestError: Error {
    case textProviderFailed
    case artifactFailed
}

private actor SemanticTestTextProvider: TextEmbeddingProviding {
    nonisolated let backendDescriptor: SimilarityBackendDescriptor
    private let shouldFail: Bool
    private var recordedQueries: [String] = []

    init(
        backendDescriptor: SimilarityBackendDescriptor = semanticTestBackend,
        shouldFail: Bool = false,
    ) {
        self.backendDescriptor = backendDescriptor
        self.shouldFail = shouldFail
    }

    func embedding(for text: String) async throws -> TextEmbedding {
        recordedQueries.append(text)
        if shouldFail {
            throw SemanticTestError.textProviderFailed
        }
        return try TextEmbedding(
            descriptor: TextEmbeddingDescriptor(
                backend: backendDescriptor,
                dimensions: semanticTestTextDescriptor.dimensions,
                tokenizerVersion: semanticTestTextDescriptor.tokenizerVersion,
            ),
            values: [1, 0],
        )
    }

    func queries() -> [String] {
        recordedQueries
    }
}

private nonisolated struct SemanticPayloadComparator: ImageTextSimilarityComparing {
    let backendDescriptor: SimilarityBackendDescriptor

    init(backendDescriptor: SimilarityBackendDescriptor = semanticTestBackend) {
        self.backendDescriptor = backendDescriptor
    }

    func similarity(
        image: SimilarityArtifact,
        text _: TextEmbedding,
    ) throws -> Float {
        guard let value = image.payload.first else {
            throw SemanticTestError.artifactFailed
        }
        if value == .max {
            throw SemanticTestError.artifactFailed
        }
        return Float(value) / 100
    }
}

private actor SemanticSearchGate {
    private struct Pending {
        let candidates: [RawCullSemanticSearchCandidate]
        let continuation: CheckedContinuation<RawCullSemanticSearchOutput, Never>
    }

    private var pending: [String: Pending] = [:]

    func suspend(
        query: String,
        candidates: [RawCullSemanticSearchCandidate],
    ) async -> RawCullSemanticSearchOutput {
        await withCheckedContinuation { continuation in
            pending[query] = Pending(
                candidates: candidates,
                continuation: continuation,
            )
        }
    }

    func waitUntilStarted(_ query: String) async {
        while pending[query] == nil {
            await Task.yield()
        }
    }

    func release(_ query: String, score: Float) {
        guard let pending = pending.removeValue(forKey: query) else { return }
        let matches = pending.candidates.map {
            RawCullSemanticSearchMatch(fileID: $0.fileID, score: score)
        }
        pending.continuation.resume(
            returning: RawCullSemanticSearchOutput(
                query: query,
                textEmbeddingDescriptor: semanticTestTextDescriptor,
                matches: matches,
                compatibleArtifactCount: matches.count,
                incompatibleArtifactCount: 0,
                failures: [],
            ),
        )
    }
}

private nonisolated struct GatedSemanticSearchService: RawCullSemanticSearchServicing {
    let backendDescriptor = semanticTestBackend
    let promptPolicyVersion = "literal-v1"
    let gate: SemanticSearchGate

    func rank(
        query: String,
        candidates: [RawCullSemanticSearchCandidate],
    ) async throws -> RawCullSemanticSearchOutput {
        await gate.suspend(query: query, candidates: candidates)
    }
}

private struct SemanticCatalogFixture {
    let root: URL
    let store: PerFileAnalysisArtifactStore
    let files: [FileItem]

    init(names: [String]) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true,
        )
        self.root = root
        self.store = PerFileAnalysisArtifactStore(
            storageDirectory: root.appendingPathComponent(
                "Similarity",
                isDirectory: true,
            ),
        )
        self.files = try names.enumerated().map { offset, name in
            let url = root.appendingPathComponent(name)
            try Data([UInt8(offset + 1)]).write(to: url, options: .atomic)
            let values = try url.resourceValues(forKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
            ])
            return FileItem(
                url: url,
                name: name,
                size: Int64(values.fileSize ?? 0),
                dateModified: values.contentModificationDate ?? .distantPast,
                exifData: nil,
                afFocusNormalized: nil,
            )
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func persistCLIPArtifacts(values: [UInt8]) async {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        var sources: [UUID: AIImageSource] = [:]
        for (offset, value) in values.enumerated()
            where files.indices.contains(offset)
        {
            let file = files[offset]
            let source = SimilarityScoringModel.source(for: file)
            sources[file.id] = source
            artifacts[file.id] = semanticArtifact(
                source: source,
                backend: semanticTestBackend,
                value: value,
            )
        }
        _ = await store.upsert(
            artifacts: artifacts,
            sources: sources,
            pipeline: SimilarityScoringModel.artifactPipelineSignature,
        )
    }
}

private nonisolated func semanticArtifact(
    source: AIImageSource,
    backend: SimilarityBackendDescriptor,
    value: UInt8,
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: backend,
            dimensions: 2,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: Data([value]),
    )
}

private nonisolated func semanticCandidate(
    id: UUID = UUID(),
    name: String,
    order: Int,
    backend: SimilarityBackendDescriptor = semanticTestBackend,
    value: UInt8,
) -> RawCullSemanticSearchCandidate {
    let source = AIImageSource(
        id: id,
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        displayName: name,
    )
    return RawCullSemanticSearchCandidate(
        fileID: id,
        fileName: name,
        catalogOrder: order,
        artifact: semanticArtifact(
            source: source,
            backend: backend,
            value: value,
        ),
    )
}

@Suite("RawCull semantic search", .tags(.smoke))
struct RawCullSemanticSearchTests {
    @Test("Literal query encodes once, excludes Vision, isolates failures, and ranks deterministically")
    func serviceRankingPolicy() async throws {
        let provider = SemanticTestTextProvider()
        let service = RawCullCLIPSemanticSearchService(
            textProvider: provider,
            comparator: SemanticPayloadComparator(),
        )
        let firstTie = semanticCandidate(name: "b.raw", order: 0, value: 50)
        let secondTie = semanticCandidate(name: "a.raw", order: 1, value: 50)
        let strongest = semanticCandidate(name: "c.raw", order: 2, value: 90)
        let vision = semanticCandidate(
            name: "vision.raw",
            order: 3,
            backend: visionOnlyTestBackend,
            value: 99,
        )
        let malformed = semanticCandidate(
            name: "malformed.raw",
            order: 4,
            value: .max,
        )

        let output = try await service.rank(
            query: "  red fox at dusk  ",
            candidates: [firstTie, secondTie, strongest, vision, malformed],
        )

        #expect(await provider.queries() == ["red fox at dusk"])
        #expect(output.query == "red fox at dusk")
        #expect(output.textEmbeddingDescriptor == semanticTestTextDescriptor)
        #expect(output.matches.map(\.fileID) == [
            strongest.fileID,
            firstTie.fileID,
            secondTie.fileID,
        ])
        #expect(output.compatibleArtifactCount == 4)
        #expect(output.incompatibleArtifactCount == 1)
        #expect(output.failures.map(\.fileID) == [malformed.fileID])
    }

    @Test("Empty query and Vision-only snapshots are distinct typed failures")
    func typedAdmissionFailures() async {
        let provider = SemanticTestTextProvider()
        let service = RawCullCLIPSemanticSearchService(
            textProvider: provider,
            comparator: SemanticPayloadComparator(),
        )

        await #expect(throws: RawCullSemanticSearchError.emptyQuery) {
            try await service.rank(query: " \n ", candidates: [])
        }
        await #expect(throws: RawCullSemanticSearchError.noCompatibleArtifacts) {
            try await service.rank(
                query: "wildlife",
                candidates: [
                    semanticCandidate(
                        name: "vision.raw",
                        order: 0,
                        backend: visionOnlyTestBackend,
                        value: 90,
                    ),
                ],
            )
        }
        #expect(await provider.queries().isEmpty)
    }

    @MainActor
    @Test("Large searches show the top twenty and preserve full CLIP diagnostics")
    func boundedResultsAndDiagnostics() async throws {
        let names = (1 ... 25).map {
            let suffix = $0 < 10 ? "0\($0)" : "\($0)"
            return "image-\(suffix).raw"
        }
        let fixture = try SemanticCatalogFixture(names: names)
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: Array(1 ... 25))
        let service = RawCullCLIPSemanticSearchService(
            textProvider: SemanticTestTextProvider(),
            comparator: SemanticPayloadComparator(),
        )
        let model = SimilarityScoringModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: service,
            artifactStore: fixture.store,
        )
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 25)

        await model.rankSemantically(
            query: "bird in flight",
            files: fixture.files,
        )

        var summary = try #require(model.semanticSearchState.resultSummary)
        #expect(summary.resultCount == 20)
        #expect(summary.rankedImageCount == 25)
        #expect(summary.hiddenRankedImageCount == 5)
        #expect(model.semanticResultOrder.count == 20)
        #expect(model.semanticSearchProgress == .scoring(
            query: "bird in flight",
            completedCount: 25,
            candidateCount: 25,
        ))

        let diagnostics = try #require(model.semanticSearchDiagnostics)
        #expect(diagnostics.query == "bird in flight")
        #expect(diagnostics.promptPolicyVersion == "literal-v1")
        #expect(diagnostics.textEmbeddingDescriptor == semanticTestTextDescriptor)
        #expect(diagnostics.results.count == 25)
        #expect(diagnostics.results.first?.fileName == "image-25.raw")
        #expect(diagnostics.results.last?.fileName == "image-01.raw")
        #expect(abs((diagnostics.highestScore ?? 0) - 0.25) < 0.0001)
        #expect(abs((diagnostics.medianScore ?? 0) - 0.13) < 0.0001)
        #expect(abs((diagnostics.lowestScore ?? 0) - 0.01) < 0.0001)
        #expect(abs((diagnostics.scoreSpread ?? 0) - 0.24) < 0.0001)
        #expect(abs((diagnostics.topScoreGap ?? 0) - 0.01) < 0.0001)

        model.setSemanticSearchShowsAllResults(true)
        summary = try #require(model.semanticSearchState.resultSummary)
        #expect(summary.resultCount == 25)
        #expect(summary.hiddenRankedImageCount == 0)
        #expect(model.semanticSearchShowsAllResults)
        #expect(model.semanticResultOrder.count == 25)

        model.setSemanticSearchShowsAllResults(false)
        summary = try #require(model.semanticSearchState.resultSummary)
        #expect(summary.resultCount == 20)
        #expect(summary.hiddenRankedImageCount == 5)
        #expect(!model.semanticSearchShowsAllResults)
        #expect(model.semanticResultOrder.count == 20)
    }

    @MainActor
    @Test("Show all updates the admitted RawCull grid without rerunning CLIP")
    func showAllUpdatesFilteredCatalog() async throws {
        let names = (1 ... 25).map { "catalog-\($0).raw" }
        let fixture = try SemanticCatalogFixture(names: names)
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: Array(1 ... 25))
        let provider = SemanticTestTextProvider()
        let service = RawCullCLIPSemanticSearchService(
            textProvider: provider,
            comparator: SemanticPayloadComparator(),
        )
        let viewModel = RawCullViewModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: service,
            similarityArtifactStore: fixture.store,
        )
        viewModel.files = fixture.files
        viewModel.filteredFiles = fixture.files
        #expect(
            await viewModel.similarityModel.hydrateSemanticArtifacts(
                fixture.files,
            ) == 25,
        )

        await viewModel.searchSemantically(for: "wildlife")
        #expect(viewModel.filteredFiles.count == 20)
        #expect(await provider.queries() == ["wildlife"])

        await viewModel.setSemanticSearchShowsAllResults(true)
        #expect(viewModel.filteredFiles.count == 25)
        #expect(await provider.queries() == ["wildlife"])

        await viewModel.setSemanticSearchShowsAllResults(false)
        #expect(viewModel.filteredFiles.count == 20)
        #expect(await provider.queries() == ["wildlife"])
    }

    @MainActor
    @Test("A superseded query cannot overwrite the newer result")
    func latestQueryWins() async throws {
        let fixture = try SemanticCatalogFixture(names: ["one.raw"])
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: [50])
        let gate = SemanticSearchGate()
        let service = GatedSemanticSearchService(gate: gate)
        let model = SimilarityScoringModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: service,
            artifactStore: fixture.store,
        )
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 1)

        let oldTask = Task {
            await model.rankSemantically(query: "old", files: fixture.files)
        }
        await gate.waitUntilStarted("old")
        let newTask = Task {
            await model.rankSemantically(query: "new", files: fixture.files)
        }
        await gate.waitUntilStarted("new")

        await gate.release("new", score: 0.9)
        await newTask.value
        await gate.release("old", score: 0.1)
        await oldTask.value

        let summary = try #require(model.semanticSearchState.resultSummary)
        #expect(summary.query == "new")
        #expect(model.semanticScores[fixture.files[0].id] == 0.9)
    }

    @MainActor
    @Test("Cancellation returns to idle and ignores a late provider response")
    func cancellationRestoresIdle() async throws {
        let fixture = try SemanticCatalogFixture(names: ["one.raw"])
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: [50])
        let gate = SemanticSearchGate()
        let service = GatedSemanticSearchService(gate: gate)
        let model = SimilarityScoringModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: service,
            artifactStore: fixture.store,
        )
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 1)

        let searchTask = Task {
            await model.rankSemantically(
                query: "cancel me",
                files: fixture.files,
            )
        }
        await gate.waitUntilStarted("cancel me")
        #expect(
            model.semanticSearchState == .searching(query: "cancel me"),
        )

        model.cancelSemanticSearch()
        #expect(model.semanticSearchState == .idle)
        #expect(model.semanticMatches.isEmpty)

        await gate.release("cancel me", score: 0.9)
        await searchTask.value
        #expect(model.semanticSearchState == .idle)
        #expect(model.semanticMatches.isEmpty)
    }

    @MainActor
    @Test("Cached-only ranking composes with rating filters and clear restores catalog order")
    func filteringAndClear() async throws {
        let fixture = try SemanticCatalogFixture(
            names: ["c.raw", "a.raw", "b.raw"],
        )
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: [90, 20, 70])
        let provider = SemanticTestTextProvider()
        let semanticService = RawCullCLIPSemanticSearchService(
            textProvider: provider,
            comparator: SemanticPayloadComparator(),
        )
        let viewModel = RawCullViewModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: semanticService,
            similarityArtifactStore: fixture.store,
        )
        viewModel.files = fixture.files
        viewModel.filteredFiles = fixture.files
        viewModel.selectedFileID = fixture.files[1].id
        viewModel.ratingCache = [
            "c.raw": 5,
            "a.raw": 0,
            "b.raw": 5,
        ]
        viewModel.ratingFilter = .stars(5)
        #expect(
            await viewModel.similarityModel.hydrateSemanticArtifacts(
                fixture.files,
            ) == 3,
        )

        await viewModel.searchSemantically(for: "night wildlife")

        #expect(viewModel.filteredFiles.map(\.name) == ["c.raw", "b.raw"])
        #expect(viewModel.selectedFileID == fixture.files[1].id)
        #expect(await provider.queries() == ["night wildlife"])

        viewModel.ratingFilter = .all
        await viewModel.clearSemanticSearch()

        #expect(viewModel.filteredFiles.map(\.name) == ["a.raw", "b.raw", "c.raw"])
        #expect(viewModel.selectedFileID == fixture.files[1].id)
    }

    @MainActor
    @Test("Partial index, empty index, provider failure, and model switch remain distinct")
    func stateCoverage() async throws {
        let fixture = try SemanticCatalogFixture(
            names: ["one.raw", "two.raw", "three.raw"],
        )
        defer { fixture.remove() }
        await fixture.persistCLIPArtifacts(values: [90, 40])
        let provider = SemanticTestTextProvider()
        let service = RawCullCLIPSemanticSearchService(
            textProvider: provider,
            comparator: SemanticPayloadComparator(),
        )
        let model = SimilarityScoringModel(
            semanticSearchCapability: .ready(
                location: nil,
                backend: semanticTestBackend,
            ),
            semanticSearchService: service,
            artifactStore: fixture.store,
        )
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 2)

        await model.rankSemantically(query: "portrait", files: fixture.files)
        let partial = try #require(model.semanticSearchState.resultSummary)
        #expect(partial.resultCount == 2)
        #expect(partial.indexedFileCount == 2)
        #expect(partial.excludedFileCount == 1)

        model.setSemanticSearchCapability(
            .unavailable(
                reason: "CLIP is missing.",
                expectedLocations: [],
            ),
            service: nil,
        )
        #expect(model.semanticSearchState == .idle)
        #expect(model.semanticMatches.isEmpty)
        await model.rankSemantically(query: "portrait", files: fixture.files)
        #expect(model.semanticSearchState == .failed(
            query: "portrait",
            message: "CLIP is missing.",
        ))

        model.setSemanticSearchCapability(
            .ready(location: nil, backend: semanticTestBackend),
            service: service,
        )
        await model.rankSemantically(query: "portrait", files: fixture.files)
        #expect(model.semanticSearchState == .emptyIndex(
            query: "portrait",
            excludedFileCount: 3,
        ))
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 2)
        #expect(model.semanticSearchState == .idle)

        let failingService = RawCullCLIPSemanticSearchService(
            textProvider: SemanticTestTextProvider(shouldFail: true),
            comparator: SemanticPayloadComparator(),
        )
        model.setSemanticSearchCapability(
            .failed(location: nil, reason: "Provider replaced for test."),
            service: nil,
        )
        model.setSemanticSearchCapability(
            .ready(location: nil, backend: semanticTestBackend),
            service: failingService,
        )
        #expect(await model.hydrateSemanticArtifacts(fixture.files) == 2)
        await model.rankSemantically(query: "portrait", files: fixture.files)
        guard case .failed(query: "portrait", _) = model.semanticSearchState else {
            Issue.record("Expected the provider-failure semantic state.")
            return
        }
    }
}

private extension RawCullSemanticSearchState {
    var resultSummary: RawCullSemanticSearchResultSummary? {
        if case let .results(summary) = self {
            summary
        } else {
            nil
        }
    }
}
