import Foundation
import Observation
import OSLog
import PhotoAIContracts
import RawCullCore

nonisolated struct RawCullSemanticSearchResultSummary: Equatable, Sendable {
    let query: String
    /// Images currently admitted to the grid.
    let resultCount: Int
    /// Every compatible image that produced a valid cosine score.
    let rankedImageCount: Int
    let indexedFileCount: Int
    let excludedFileCount: Int
    let scoringFailureCount: Int

    init(
        query: String,
        resultCount: Int,
        rankedImageCount: Int? = nil,
        indexedFileCount: Int,
        excludedFileCount: Int,
        scoringFailureCount: Int,
    ) {
        self.query = query
        self.resultCount = resultCount
        self.rankedImageCount = rankedImageCount ?? resultCount
        self.indexedFileCount = indexedFileCount
        self.excludedFileCount = excludedFileCount
        self.scoringFailureCount = scoringFailureCount
    }

    var hiddenRankedImageCount: Int {
        max(0, rankedImageCount - resultCount)
    }
}

nonisolated enum RawCullSemanticSearchState: Equatable, Sendable {
    case idle
    case searching(query: String)
    case results(RawCullSemanticSearchResultSummary)
    case emptyIndex(query: String, excludedFileCount: Int)
    case failed(query: String, message: String)
}

private nonisolated enum SemanticSearchTaskResult: Sendable {
    case success(RawCullSemanticSearchOutput)
    case failure(String)
    case emptyIndex
    case cancelled
}

/// Owns cached semantic evidence, provider configuration, and search lifetime.
@MainActor
@Observable
final class RawCullSemanticSearchModel {
    nonisolated static let semanticSearchDefaultResultLimit = 20
    private(set) var gridContentRevision: UInt64 = 0
    private(set) var semanticSearchCapability: RawCullSemanticSearchCapabilityStatus
    private(set) var semanticSearchState = RawCullSemanticSearchState.idle {
        didSet { gridContentRevision &+= 1 }
    }

    private(set) var semanticMatches: [RawCullSemanticSearchMatch] = []
    private(set) var semanticScores: [UUID: Float] = [:]
    private(set) var semanticResultOrder: [UUID: Int] = [:] {
        didSet { gridContentRevision &+= 1 }
    }

    private(set) var semanticSearchProgress: RawCullSemanticSearchProgress?
    private(set) var semanticIndexedFileCount = 0
    private(set) var semanticCatalogFileCount = 0

    var semanticSearchSelectionCount: Int {
        semanticResultOrder.count
    }

    var semanticSearchSelectedFileIDs: Set<UUID> {
        Set(semanticResultOrder.keys)
    }

    var hasSemanticSearchResults: Bool {
        if case .results = semanticSearchState {
            true
        } else {
            false
        }
    }

    var semanticSearchHasEmptyIndex: Bool {
        if case .emptyIndex = semanticSearchState {
            true
        } else {
            false
        }
    }

    @ObservationIgnored private var semanticSearchService:
        (any RawCullSemanticSearchServicing)?
    @ObservationIgnored private var semanticArtifacts: [UUID: SimilarityArtifact] = [:]
    @ObservationIgnored private var _semanticSearchTask:
        Task<SemanticSearchTaskResult, Never>?
    @ObservationIgnored private var _semanticSearchGeneration = 0
    @ObservationIgnored private var _semanticHydrationGeneration = 0
    @ObservationIgnored private let artifactStore: any SimilarityArtifactStoring

    init(
        capability: RawCullSemanticSearchCapabilityStatus,
        service: (any RawCullSemanticSearchServicing)?,
        artifactStore: any SimilarityArtifactStoring,
    ) {
        semanticSearchCapability = capability
        semanticSearchService = service
        self.artifactStore = artifactStore
    }

    var semanticSearchBackendDescriptor: SimilarityBackendDescriptor? {
        semanticSearchService?.backendDescriptor
    }

    func reset() {
        cancelSemanticSearch()
        _semanticHydrationGeneration &+= 1
        semanticArtifacts = [:]
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticIndexedFileCount = 0
        semanticCatalogFileCount = 0
        semanticSearchState = .idle
    }

    func cancelSemanticSearch() {
        _semanticSearchTask?.cancel()
        _semanticSearchTask = nil
        _semanticSearchGeneration &+= 1
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticSearchState = .idle
    }

    func clearSemanticSearch() {
        cancelSemanticSearch()
    }

    func setSemanticSearchCapability(
        _ capability: RawCullSemanticSearchCapabilityStatus,
        service: (any RawCullSemanticSearchServicing)?,
    ) {
        let currentDescriptor = semanticSearchService?.backendDescriptor
        let replacementDescriptor = service?.backendDescriptor
        guard semanticSearchCapability != capability
            || currentDescriptor != replacementDescriptor
        else { return }

        cancelSemanticSearch()
        _semanticHydrationGeneration &+= 1
        semanticSearchCapability = capability
        semanticSearchService = service
        semanticArtifacts = [:]
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil
        semanticIndexedFileCount = 0
        semanticCatalogFileCount = 0
        semanticSearchState = .idle
    }

    func hydrateSemanticArtifacts(_ files: [FileItem]) async -> Int {
        _semanticHydrationGeneration &+= 1
        let generation = _semanticHydrationGeneration
        semanticCatalogFileCount = files.count

        guard let service = semanticSearchService, !files.isEmpty else {
            semanticArtifacts = [:]
            semanticIndexedFileCount = 0
            return 0
        }

        let backend = service.backendDescriptor
        let sources = files.map(SimilarityScoringModel.source(for:))
        let loadResult = await artifactStore.load(
            sources: sources,
            allowedBackends: [backend],
            pipeline: SimilarityScoringModel.artifactPipelineSignature,
        )
        guard generation == _semanticHydrationGeneration,
              semanticSearchService?.backendDescriptor == backend,
              !Task.isCancelled
        else { return 0 }

        let sourcesByID = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })
        semanticArtifacts = loadResult.artifacts.filter { id, artifact in
            guard let source = sourcesByID[id] else { return false }
            return RawCullSimilarityArtifactValidation.isCurrent(
                artifact,
                for: source,
                backend: backend,
            )
        }
        semanticIndexedFileCount = semanticArtifacts.count
        dismissStaleEmptySemanticIndexState()
        return semanticIndexedFileCount
    }

    func classifySubjects(in files: [FileItem]) async -> [UUID: String] {
        guard let service = semanticSearchService else { return [:] }
        let candidates = files.enumerated().compactMap {
            element -> RawCullSemanticSearchCandidate? in
            let (offset, file) = element
            guard let artifact = semanticArtifacts[file.id] else { return nil }
            return RawCullSemanticSearchCandidate(
                fileID: file.id,
                fileName: file.name,
                catalogOrder: offset,
                artifact: artifact,
            )
        }
        guard !candidates.isEmpty else { return [:] }

        let prompts: [(label: String, text: String)] = [
            ("person", "a photo of a person"),
            ("bird", "a photo of a bird"),
            ("deer", "a photo of a deer"),
            ("animal", "a photo of an animal"),
            ("car", "a photo of a car"),
            ("landscape", "a landscape photo")
        ]
        var bestByID: [UUID: (label: String, score: Float)] = [:]
        for prompt in prompts {
            guard !Task.isCancelled else { return [:] }
            guard let output = try? await service.rank(
                query: prompt.text,
                candidates: candidates,
            ) else { continue }
            for match in output.matches
                where match.score > (bestByID[match.fileID]?.score ?? -.infinity) {
                bestByID[match.fileID] = (prompt.label, match.score)
            }
        }
        return bestByID.mapValues(\.label)
    }

    func rankSemantically(
        query: String,
        files: [FileItem],
    ) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            clearSemanticSearch()
            return
        }

        cancelSemanticSearch()
        let generation = _semanticSearchGeneration
        semanticMatches = []
        semanticScores = [:]
        semanticResultOrder = [:]
        semanticSearchProgress = nil

        guard let service = semanticSearchService else {
            semanticSearchState = .failed(
                query: trimmedQuery,
                message: Self.semanticUnavailableReason(semanticSearchCapability),
            )
            return
        }

        let candidates: [RawCullSemanticSearchCandidate] = files.enumerated().compactMap {
            element -> RawCullSemanticSearchCandidate? in
            let (offset, file) = element
            guard let artifact = semanticArtifacts[file.id] else { return nil }
            return RawCullSemanticSearchCandidate(
                fileID: file.id,
                fileName: file.name,
                catalogOrder: offset,
                artifact: artifact,
            )
        }
        let admittedFileCount = files.count
        guard !candidates.isEmpty else {
            semanticSearchState = .emptyIndex(
                query: trimmedQuery,
                excludedFileCount: admittedFileCount,
            )
            return
        }

        semanticSearchProgress = .encodingText(
            query: trimmedQuery,
            candidateCount: candidates.count,
        )
        semanticSearchState = .searching(query: trimmedQuery)
        let progressHandler: @Sendable (
            RawCullSemanticSearchProgress,
        ) async -> Void = { [model = self] progress in
            await model.acceptSemanticSearchProgress(
                progress,
                generation: generation,
            )
        }
        let work = Task<SemanticSearchTaskResult, Never> { @concurrent in
            do {
                return try await .success(
                    service.rank(
                        query: trimmedQuery,
                        candidates: candidates,
                        progress: progressHandler,
                    ),
                )
            } catch is CancellationError {
                return .cancelled
            } catch RawCullSemanticSearchError.noCompatibleArtifacts {
                return .emptyIndex
            } catch {
                return .failure(String(describing: error))
            }
        }
        _semanticSearchTask = work
        let result = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }

        if _semanticSearchTask == work {
            _semanticSearchTask = nil
        }
        guard _semanticSearchGeneration == generation,
              !work.isCancelled,
              !Task.isCancelled
        else {
            if _semanticSearchGeneration == generation {
                semanticSearchState = .idle
            }
            return
        }

        switch result {
        case let .success(output):
            semanticMatches = output.matches
            semanticScores = Dictionary(
                uniqueKeysWithValues: output.matches.map {
                    ($0.fileID, $0.score)
                },
            )
            semanticSearchProgress = .scoring(
                query: output.query,
                completedCount: output.compatibleArtifactCount,
                candidateCount: output.compatibleArtifactCount,
            )
            applySemanticSearchResultPresentation(
                output: output,
                admittedFileCount: admittedFileCount,
            )
            if !output.failures.isEmpty {
                Logger.process.warning(
                    "SimilarityScoringModel: \(output.failures.count) cached CLIP artifacts failed semantic scoring",
                )
            }

        case .emptyIndex:
            semanticSearchProgress = nil
            semanticSearchState = .emptyIndex(
                query: trimmedQuery,
                excludedFileCount: admittedFileCount,
            )

        case let .failure(message):
            semanticSearchProgress = nil
            semanticSearchState = .failed(
                query: trimmedQuery,
                message: message,
            )

        case .cancelled:
            semanticSearchProgress = nil
            semanticSearchState = .idle
        }
    }

    func setSemanticSearchShowsAllResults(_ showsAll: Bool) {
        let count = showsAll
            ? semanticMatches.count
            : min(
                Self.semanticSearchDefaultResultLimit,
                semanticMatches.count,
            )
        setSemanticSearchSelectionCount(count)
    }

    func adjustSemanticSearchSelection(by delta: Int) {
        guard delta != 0 else { return }
        setSemanticSearchSelectionCount(
            semanticSearchSelectionCount + delta,
        )
    }

    func setSemanticSearchSelectionCount(_ requestedCount: Int) {
        guard !semanticMatches.isEmpty,
              case let .results(summary) = semanticSearchState
        else { return }

        let selectedCount = min(
            max(1, requestedCount),
            semanticMatches.count,
        )
        guard selectedCount != semanticSearchSelectionCount else { return }

        let selectedMatches = semanticMatches.prefix(selectedCount)
        semanticResultOrder = Dictionary(
            uniqueKeysWithValues: selectedMatches.enumerated().map {
                ($0.element.fileID, $0.offset)
            },
        )
        semanticSearchState = .results(
            RawCullSemanticSearchResultSummary(
                query: summary.query,
                resultCount: selectedCount,
                rankedImageCount: summary.rankedImageCount,
                indexedFileCount: summary.indexedFileCount,
                excludedFileCount: summary.excludedFileCount,
                scoringFailureCount: summary.scoringFailureCount,
            ),
        )
    }

    private func acceptSemanticSearchProgress(
        _ progress: RawCullSemanticSearchProgress,
        generation: Int,
    ) {
        guard _semanticSearchGeneration == generation,
              case let .searching(activeQuery) = semanticSearchState,
              activeQuery == progress.query
        else { return }
        semanticSearchProgress = progress
    }

    private func applySemanticSearchResultPresentation(
        output: RawCullSemanticSearchOutput,
        admittedFileCount: Int,
    ) {
        let visibleMatches = output.matches.prefix(
            Self.semanticSearchDefaultResultLimit,
        )
        semanticResultOrder = Dictionary(
            uniqueKeysWithValues: visibleMatches.enumerated().map {
                ($0.element.fileID, $0.offset)
            },
        )
        semanticSearchState = .results(
            RawCullSemanticSearchResultSummary(
                query: output.query,
                resultCount: visibleMatches.count,
                rankedImageCount: output.matches.count,
                indexedFileCount: output.compatibleArtifactCount,
                excludedFileCount: max(
                    0,
                    admittedFileCount - output.matches.count,
                ),
                scoringFailureCount: output.failures.count,
            ),
        )
    }

    private func dismissStaleEmptySemanticIndexState() {
        guard semanticIndexedFileCount > 0,
              case .emptyIndex = semanticSearchState
        else { return }
        semanticSearchState = .idle
    }

    private nonisolated static func semanticUnavailableReason(
        _ capability: RawCullSemanticSearchCapabilityStatus,
    ) -> String {
        switch capability {
        case .checking:
            "Semantic search capability is still being checked."

        case .ready:
            "The semantic-search provider is not available."

        case let .unavailable(reason, _):
            reason

        case let .failed(_, reason):
            reason
        }
    }

    func noteCatalogFileCount(_ count: Int) {
        if semanticSearchService != nil { semanticCatalogFileCount = count }
    }

    /// Indexing replaces matching artifacts; legacy import preserves existing ones.
    func acceptArtifacts(
        _ artifacts: [UUID: SimilarityArtifact],
        sources: [UUID: AIImageSource],
        preservingExisting: Bool,
        catalogFileCount: Int? = nil,
    ) {
        if let backend = semanticSearchBackendDescriptor {
            let compatible = artifacts.filter { id, artifact in
                guard let source = sources[id] else { return false }
                return RawCullSimilarityArtifactValidation.isCurrent(artifact, for: source, backend: backend)
            }
            semanticArtifacts.merge(compatible) { current, incoming in
                preservingExisting ? current : incoming
            }
            if let catalogFileCount { semanticCatalogFileCount = catalogFileCount }
        }
        semanticIndexedFileCount = semanticArtifacts.count
        dismissStaleEmptySemanticIndexState()
    }
}
