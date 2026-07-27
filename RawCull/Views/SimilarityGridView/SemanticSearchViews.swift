//
//  SemanticSearchViews.swift
//  RawCull
//
//  Capability-aware semantic-search controls and workflow states.
//

import Foundation
import SwiftUI

struct SemanticSearchControlsView: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SemanticSearchTitleRow(
                presentation: presentation,
            )

            switch presentation.availability {
            case .ready:
                SemanticSearchQueryEntryView(
                    viewModel: viewModel,
                    presentation: presentation,
                )
                SemanticSearchReadinessView(
                    presentation: presentation,
                    onIndex: indexSimilarity,
                    onCancelIndexing: viewModel.similarityModel.cancelIndexing,
                )

            case let .checking(expectedLocations):
                SemanticSearchUnavailableView(
                    mode: .checking,
                    reason: nil,
                    location: expectedLocations.first,
                )

            case let .unavailable(reason, expectedLocations):
                SemanticSearchUnavailableView(
                    mode: .unavailable,
                    reason: reason,
                    location: expectedLocations.first,
                )

            case let .failed(location, reason):
                SemanticSearchUnavailableView(
                    mode: .failed,
                    reason: reason,
                    location: location,
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Semantic search")
    }

    private var presentation: SemanticSearchUIPresentation {
        let model = viewModel.similarityModel
        return SemanticSearchUIPresentation(
            capability: model.semanticSearchCapability,
            searchState: model.semanticSearchState,
            indexedFileCount: model.semanticIndexedFileCount,
            catalogFileCount: model.semanticCatalogFileCount,
            isIndexing: model.isIndexing
                && model.canIndexSemanticSearchArtifacts,
            indexingProgress: model.indexingProgress,
            indexingTotal: model.indexingTotal,
            indexingPhase: model.indexingPhase,
            activeBackendCanIndex: model.canIndexSemanticSearchArtifacts,
        )
    }

    private func indexSimilarity() {
        guard presentation.canStartIndexing else { return }
        Task {
            await viewModel.indexSimilarity()
        }
    }
}

private struct SemanticSearchQueryEntryView: View {
    @Bindable var viewModel: RawCullViewModel
    let presentation: SemanticSearchUIPresentation

    @State private var queryText = ""
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    "Describe the images you want to find",
                    text: $queryText,
                )
                .textFieldStyle(.roundedBorder)
                .focused($searchFieldFocused)
                .onSubmit(submitSearch)
                .accessibilityLabel("Semantic search query")
                .accessibilityHint("Press Return to rank compatible indexed images.")

                if presentation.canCancelSearch {
                    Button("Cancel", role: .cancel, action: cancelSearch)
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityHint("Cancels the current query and returns to catalog order.")
                } else {
                    Button(action: submitSearch) {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !presentation.canSubmitSearch,
                    )
                    .accessibilityHint("Ranks images using cached CLIP artifacts.")
                }

                if !queryText.isEmpty
                    || viewModel.similarityModel.semanticSearchState != .idle {
                    Button(action: clearSearch) {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Clears the query and restores catalog order.")
                }
            }

            if queryText.isEmpty, presentation.activity == .idle {
                HStack(spacing: 6) {
                    Text("Try")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    exampleQueryButton("red fox at dusk")
                    exampleQueryButton("backlit portrait")
                    exampleQueryButton("misty mountain")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Example semantic search queries")
            }
        }
        .onChange(of: queryText) {
            guard queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  viewModel.similarityModel.semanticSearchState != .idle
            else { return }
            clearSearch()
        }
    }

    private func exampleQueryButton(
        _ query: LocalizedStringResource,
    ) -> some View {
        Button(query) {
            let localizedQuery = String(localized: query)
            queryText = localizedQuery
            submitSearch()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityHint("Uses this example as a semantic search query.")
    }

    private func submitSearch() {
        let query = queryText.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        guard !query.isEmpty, presentation.canSubmitSearch else { return }
        queryText = query
        searchTask?.cancel()
        searchTask = Task {
            await viewModel.searchSemantically(for: query)
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        viewModel.similarityModel.cancelSemanticSearch()
        Task {
            await viewModel.cancelSemanticSearch()
        }
    }

    private func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        queryText = ""
        viewModel.similarityModel.clearSemanticSearch()
        searchFieldFocused = true
        Task {
            await viewModel.clearSemanticSearch()
        }
    }
}

private struct SemanticSearchTitleRow: View {
    let presentation: SemanticSearchUIPresentation

    var body: some View {
        HStack(spacing: 10) {
            Label("Semantic Search", systemImage: "text.magnifyingglass")
                .font(.headline)

            Spacer(minLength: 12)

            if presentation.showsSearchField {
                Text(
                    "\(presentation.coverage.indexedFileCount) of \(presentation.coverage.catalogFileCount) indexed",
                    comment: "Semantic-search coverage: first value is indexed images and second is all catalog images.",
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(
                    presentation.coverage.isComplete
                        ? Color.green
                        : Color.secondary,
                )
                .accessibilityLabel("Semantic search indexing coverage")
                .accessibilityValue(
                    "\(presentation.coverage.indexedFileCount) of \(presentation.coverage.catalogFileCount) images",
                )
            }
        }
    }
}

private struct SemanticSearchReadinessView: View {
    let presentation: SemanticSearchUIPresentation
    let onIndex: () -> Void
    let onCancelIndexing: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            activityStatus

            Spacer(minLength: 12)

            if presentation.isIndexing {
                Button("Cancel Indexing", role: .cancel, action: onCancelIndexing)
                    .buttonStyle(.bordered)
            } else if presentation.showsIndexSimilarityAction {
                if presentation.activeBackendCanIndex {
                    Button("Index Similarity", action: onIndex)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Builds compatible CLIP artifacts for missing catalog images.")
                } else {
                    Text("Enable “Use CLIP for similarity” in AI Settings before indexing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SettingsLink {
                        Label("Open AI Settings", systemImage: "gear")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var activityStatus: some View {
        switch presentation.activity {
        case .idle:
            coverageStatus

        case let .indexing(completed, total, phase):
            HStack(spacing: 8) {
                if total > 0 {
                    ProgressView(
                        value: Double(completed),
                        total: Double(total),
                    )
                    .frame(maxWidth: 180)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(indexingStatus(completed: completed, total: total, phase: phase))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

        case let .searching(query):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Ranking cached images for “\(query)”…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case let .results(summary):
            resultStatus(summary)

        case let .emptyResults(summary):
            resultStatus(summary)

        case let .emptyIndex(_, excludedFileCount):
            Text("\(excludedFileCount) images are excluded because no compatible CLIP artifacts are available.")
                .font(.caption)
                .foregroundStyle(.orange)

        case let .failed(_, message):
            Text("Search failed: \(message)")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }

    private var coverageStatus: some View {
        HStack(spacing: 6) {
            Image(
                systemName: presentation.coverage.isComplete
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle",
            )
            .foregroundStyle(
                presentation.coverage.isComplete ? .green : .orange,
            )
            .accessibilityHidden(true)

            if presentation.coverage.catalogFileCount == 0 {
                Text("Open a catalog to index images for semantic search.")
            } else if presentation.coverage.excludedFileCount == 0 {
                Text("All catalog images have compatible CLIP artifacts.")
            } else {
                Text(
                    "\(presentation.coverage.excludedFileCount) catalog images are not yet searchable.",
                    comment: "Count of catalog images excluded from semantic search because they are not indexed.",
                )
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func resultStatus(
        _ summary: RawCullSemanticSearchResultSummary,
    ) -> some View {
        HStack(spacing: 6) {
            Text(
                "\(summary.resultCount) ranked results",
                comment: "Count of semantic-search results.",
            )
            if summary.excludedFileCount > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(
                    "\(summary.excludedFileCount) excluded",
                    comment: "Count of images excluded from semantic-search results.",
                )
                .foregroundStyle(.orange)
            }
            if summary.scoringFailureCount > 0 {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(
                    "\(summary.scoringFailureCount) could not be scored",
                    comment: "Count of cached artifacts that failed semantic scoring.",
                )
                .foregroundStyle(.orange)
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func indexingStatus(
        completed: Int,
        total: Int,
        phase: SimilarityIndexingPhase,
    ) -> LocalizedStringResource {
        switch phase {
        case .idle:
            "Preparing similarity indexing…"

        case .generating:
            "Indexing \(completed) of \(total) images…"

        case .saving:
            "Saving \(completed) of \(total) artifacts…"
        }
    }
}
