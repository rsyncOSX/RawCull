//
//  SemanticSearchViews.swift
//  RawCull
//
//  Capability-aware semantic-search controls and workflow states.
//

import Foundation
import SwiftUI

struct SemanticSearchControlsView: View {
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let similarityFeature: RawCullSimilarityFeature

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SemanticSearchTitleRow()

            switch presentation.availability {
            case .ready:
                SemanticSearchQueryEntryView(
                    semanticSearchFeature: semanticSearchFeature,
                    presentation: presentation,
                    onIndex: indexSimilarity,
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
        .accessibilityValue(RawCullAccessibilityPresentation.semanticSearchValue(presentation))
    }

    private var presentation: SemanticSearchUIPresentation {
        semanticSearchFeature.presentation
    }

    private func indexSimilarity() {
        guard presentation.canStartIndexing else { return }
        Task { await similarityFeature.indexCurrentCatalog() }
    }
}

private struct SemanticSearchQueryEntryView: View {
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let presentation: SemanticSearchUIPresentation
    let onIndex: () -> Void

    @State private var queryText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var isClearingSearch = false
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(
                    "Describe the images you want to find",
                    text: $queryText,
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
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
                    || semanticSearchFeature.state != .idle {
                    Button(action: clearSearch) {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Clears the query and restores catalog order.")
                }

                SemanticSearchReadinessView(
                    presentation: presentation,
                    onIndex: onIndex,
                )
            }

            HStack(spacing: 6) {
                Text("Try")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                exampleQueryButton("red fox at dusk")
                exampleQueryButton("backlit portrait")
                exampleQueryButton("misty mountain")
            }
            .opacity(showsExampleQueries ? 1 : 0)
            .allowsHitTesting(showsExampleQueries)
            .accessibilityHidden(!showsExampleQueries)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Example semantic search queries")
        }
        .onChange(of: queryText) {
            guard !isClearingSearch,
                  queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  semanticSearchFeature.state != .idle
            else { return }
            clearSearch()
        }
    }

    private var showsExampleQueries: Bool {
        queryText.isEmpty && presentation.activity == .idle
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
            await semanticSearchFeature.search(for: query)
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        Task {
            await semanticSearchFeature.cancel()
        }
    }

    private func clearSearch() {
        guard !isClearingSearch else { return }
        isClearingSearch = true
        searchTask?.cancel()
        queryText = ""
        searchTask = Task {
            defer { isClearingSearch = false }
            await semanticSearchFeature.clear()
            guard !Task.isCancelled else { return }
            searchFieldFocused = true
        }
    }
}

private struct SemanticSearchTitleRow: View {
    var body: some View {
        Label("Semantic Search", systemImage: "text.magnifyingglass")
            .font(.headline)
    }
}

private struct SemanticSearchReadinessView: View {
    let presentation: SemanticSearchUIPresentation
    let onIndex: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SemanticSearchActivityStatusView(
                activity: presentation.activity,
                coverage: presentation.coverage,
            )
            .lineLimit(1)

            Spacer(minLength: 12)

            if presentation.showsIndexSimilarityAction, !presentation.isIndexing {
                if presentation.activeBackendCanIndex {
                    Button("Index Similarity", action: onIndex)
                        .buttonStyle(.bordered)
                        .accessibilityHint("Builds compatible CLIP artifacts for missing catalog images.")
                } else {
                    Text(
                        "Enable “Use selected CLIP model for similarity” in AI Settings before indexing.",
                    )
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
}

private struct SemanticSearchActivityStatusView: View {
    let activity: SemanticSearchUIActivity
    let coverage: SemanticSearchUICoverage

    var body: some View {
        switch activity {
        case .idle:
            coverageStatus

        case let .indexing(completed, total, phase):
            Label("Catalog setup continues in Burst Groups below.", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHint(indexingStatus(completed: completed, total: total, phase: phase))

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
        }
    }

    private var coverageStatus: some View {
        HStack(spacing: 6) {
            Image(
                systemName: coverage.isComplete
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle",
            )
            .foregroundStyle(
                coverage.isComplete ? .green : .orange,
            )
            .accessibilityHidden(true)

            if coverage.catalogFileCount == 0 {
                Text("Open a catalog to index images for semantic search.")
            } else if coverage.excludedFileCount == 0 {
                Text("All catalog images have compatible CLIP artifacts.")
            } else {
                Text(
                    "\(coverage.excludedFileCount) catalog images are not yet searchable.",
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
            if summary.hiddenRankedImageCount > 0 {
                Text(
                    "\(summary.resultCount) shown · \(summary.rankedImageCount) images ranked",
                    comment: "Visible semantic results followed by every successfully ranked image.",
                )
            } else {
                Text(
                    "\(summary.rankedImageCount) images ranked",
                    comment: "Count of successfully ranked semantic-search images.",
                )
            }
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
