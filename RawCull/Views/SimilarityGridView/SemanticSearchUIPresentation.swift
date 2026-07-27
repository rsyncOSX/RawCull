//
//  SemanticSearchUIPresentation.swift
//  RawCull
//
//  Deterministic presentation state for the semantic-search workflow.
//

import Foundation
import PhotoAIContracts

nonisolated enum SemanticSearchUIAvailability: Equatable, Sendable {
    case checking(expectedLocations: [URL])
    case ready(location: URL?, backend: SimilarityBackendDescriptor)
    case unavailable(reason: String, expectedLocations: [URL])
    case failed(location: URL?, reason: String)
}

nonisolated struct SemanticSearchUICoverage: Equatable, Sendable {
    let indexedFileCount: Int
    let catalogFileCount: Int

    var excludedFileCount: Int {
        max(0, catalogFileCount - indexedFileCount)
    }

    var isComplete: Bool {
        catalogFileCount > 0 && excludedFileCount == 0
    }
}

nonisolated enum SemanticSearchUIActivity: Equatable, Sendable {
    case idle
    case indexing(
        completed: Int,
        total: Int,
        phase: SimilarityIndexingPhase,
    )
    case searching(query: String)
    case results(RawCullSemanticSearchResultSummary)
    case emptyResults(RawCullSemanticSearchResultSummary)
    case emptyIndex(query: String, excludedFileCount: Int)
    case failed(query: String, message: String)
}

nonisolated struct SemanticSearchUIPresentation: Equatable, Sendable {
    let availability: SemanticSearchUIAvailability
    let coverage: SemanticSearchUICoverage
    let activity: SemanticSearchUIActivity
    let activeBackendCanIndex: Bool

    init(
        capability: RawCullSemanticSearchCapabilityStatus,
        searchState: RawCullSemanticSearchState,
        indexedFileCount: Int,
        catalogFileCount: Int,
        isIndexing: Bool,
        indexingProgress: Int,
        indexingTotal: Int,
        indexingPhase: SimilarityIndexingPhase,
        activeBackendCanIndex: Bool,
    ) {
        availability = Self.availability(for: capability)
        coverage = SemanticSearchUICoverage(
            indexedFileCount: indexedFileCount,
            catalogFileCount: catalogFileCount,
        )
        activity = Self.activity(
            searchState: searchState,
            isIndexing: isIndexing,
            indexingProgress: indexingProgress,
            indexingTotal: indexingTotal,
            indexingPhase: indexingPhase,
        )
        self.activeBackendCanIndex = activeBackendCanIndex
    }

    private static func availability(
        for capability: RawCullSemanticSearchCapabilityStatus,
    ) -> SemanticSearchUIAvailability {
        switch capability {
        case let .checking(expectedLocations):
            .checking(expectedLocations: expectedLocations)

        case let .ready(location, backend):
            .ready(location: location, backend: backend)

        case let .unavailable(reason, expectedLocations):
            .unavailable(
                reason: reason,
                expectedLocations: expectedLocations,
            )

        case let .failed(location, reason):
            .failed(location: location, reason: reason)
        }
    }

    private static func activity(
        searchState: RawCullSemanticSearchState,
        isIndexing: Bool,
        indexingProgress: Int,
        indexingTotal: Int,
        indexingPhase: SimilarityIndexingPhase,
    ) -> SemanticSearchUIActivity {
        if isIndexing {
            return .indexing(
                completed: indexingProgress,
                total: indexingTotal,
                phase: indexingPhase,
            )
        }
        return switch searchState {
        case .idle:
            .idle

        case let .searching(query):
            .searching(query: query)

        case let .results(summary) where summary.resultCount == 0:
            .emptyResults(summary)

        case let .results(summary):
            .results(summary)

        case let .emptyIndex(query, excludedFileCount):
            .emptyIndex(
                query: query,
                excludedFileCount: excludedFileCount,
            )

        case let .failed(query, message):
            .failed(query: query, message: message)
        }
    }

    var showsSearchField: Bool {
        if case .ready = availability {
            true
        } else {
            false
        }
    }

    var canSubmitSearch: Bool {
        showsSearchField && !isIndexing
    }

    var showsIndexSimilarityAction: Bool {
        showsSearchField && coverage.excludedFileCount > 0
    }

    var canStartIndexing: Bool {
        showsIndexSimilarityAction
            && activeBackendCanIndex
            && !isIndexing
    }

    var isIndexing: Bool {
        if case .indexing = activity {
            true
        } else {
            false
        }
    }

    var canCancelSearch: Bool {
        if case .searching = activity {
            true
        } else {
            false
        }
    }
}
