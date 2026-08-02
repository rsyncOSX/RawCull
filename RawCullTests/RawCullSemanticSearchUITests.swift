import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

private nonisolated let semanticUIBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "semantic-ui-test-v1",
    representation: "float32-l2-normalized",
    preprocessingVersion: "semantic-ui-preprocess-v1",
    normalizationVersion: "semantic-ui-normalization-v1",
    configurationVersion: "semantic-ui-config-v1",
)

private nonisolated func semanticUIPresentation(
    capability: RawCullSemanticSearchCapabilityStatus = .ready(
        location: nil,
        backend: semanticUIBackend,
    ),
    searchState: RawCullSemanticSearchState = .idle,
    indexedFileCount: Int = 7,
    catalogFileCount: Int = 10,
    isIndexing: Bool = false,
    indexingProgress: Int = 0,
    indexingTotal: Int = 0,
    indexingPhase: SimilarityIndexingPhase = .idle,
    activeBackendCanIndex: Bool = true,
) -> SemanticSearchUIPresentation {
    SemanticSearchUIPresentation(
        capability: capability,
        searchState: searchState,
        indexedFileCount: indexedFileCount,
        catalogFileCount: catalogFileCount,
        isIndexing: isIndexing,
        indexingProgress: indexingProgress,
        indexingTotal: indexingTotal,
        indexingPhase: indexingPhase,
        activeBackendCanIndex: activeBackendCanIndex,
    )
}

@Suite("RawCull semantic search UI", .tags(.smoke))
struct RawCullSemanticSearchUITests {
    @Test
    func capabilityControls() {
        let ready = semanticUIPresentation()
        #expect(ready.showsSearchField)
        #expect(ready.canSubmitSearch)
        #expect(ready.showsIndexSimilarityAction)
        #expect(ready.canStartIndexing)
        #expect(ready.coverage.excludedFileCount == 3)

        let unavailable = semanticUIPresentation(
            capability: .unavailable(
                reason: "CLIP model is missing.",
                expectedLocations: [
                    URL(fileURLWithPath: "/tmp/RawCull/Models/CLIP-OpenAI")
                ],
            ),
        )
        #expect(!unavailable.showsSearchField)
        #expect(!unavailable.canSubmitSearch)
        #expect(!unavailable.showsIndexSimilarityAction)
        guard case let .unavailable(reason, locations) =
            unavailable.availability
        else {
            Issue.record("Expected unavailable semantic-search UI.")
            return
        }
        #expect(reason == "CLIP model is missing.")
        #expect(locations.count == 1)
    }

    @Test
    func indexingState() {
        let presentation = semanticUIPresentation(
            searchState: .results(
                RawCullSemanticSearchResultSummary(
                    query: "wildlife",
                    resultCount: 7,
                    indexedFileCount: 7,
                    excludedFileCount: 3,
                    scoringFailureCount: 0,
                ),
            ),
            isIndexing: true,
            indexingProgress: 4,
            indexingTotal: 10,
            indexingPhase: .generating,
        )

        #expect(presentation.isIndexing)
        #expect(!presentation.canSubmitSearch)
        #expect(!presentation.canStartIndexing)
        guard case let .indexing(completed, total, phase) =
            presentation.activity
        else {
            Issue.record("Expected indexing semantic-search UI.")
            return
        }
        #expect(completed == 4)
        #expect(total == 10)
        #expect(phase == .generating)
    }

    @Test
    func resultStates() {
        let partialSummary = RawCullSemanticSearchResultSummary(
            query: "backlit portrait",
            resultCount: 7,
            rankedImageCount: 12,
            indexedFileCount: 12,
            excludedFileCount: 3,
            scoringFailureCount: 1,
        )
        let partial = semanticUIPresentation(
            searchState: .results(partialSummary),
        )
        #expect(partial.activity == .results(partialSummary))
        #expect(partialSummary.hiddenRankedImageCount == 5)

        let emptySummary = RawCullSemanticSearchResultSummary(
            query: "misty mountain",
            resultCount: 0,
            indexedFileCount: 2,
            excludedFileCount: 8,
            scoringFailureCount: 2,
        )
        let emptyResults = semanticUIPresentation(
            searchState: .results(emptySummary),
        )
        #expect(emptyResults.activity == .emptyResults(emptySummary))

        let emptyIndex = semanticUIPresentation(
            searchState: .emptyIndex(
                query: "red fox",
                excludedFileCount: 10,
            ),
            indexedFileCount: 0,
        )
        #expect(
            emptyIndex.activity == .emptyIndex(
                query: "red fox",
                excludedFileCount: 10,
            ),
        )

        let failure = semanticUIPresentation(
            searchState: .failed(
                query: "night wildlife",
                message: "Text encoding failed.",
            ),
        )
        #expect(
            failure.activity == .failed(
                query: "night wildlife",
                message: "Text encoding failed.",
            ),
        )
    }

    @Test
    func cancellationAndClearState() {
        let searching = semanticUIPresentation(
            searchState: .searching(query: "red fox at dusk"),
        )
        #expect(searching.canCancelSearch)
        #expect(
            searching.activity == .searching(query: "red fox at dusk"),
        )

        let cleared = semanticUIPresentation(searchState: .idle)
        #expect(!cleared.canCancelSearch)
        #expect(cleared.activity == .idle)
    }
}
