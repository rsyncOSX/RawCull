//
//  SemanticSearchStateViews.swift
//  RawCull
//
//  Content states for the semantic-search workflow.
//

import Foundation
import SwiftUI

struct SemanticSearchUnavailableView: View {
    enum Mode: Equatable {
        case checking
        case unavailable
        case failed
    }

    let mode: Mode
    let reason: String?
    let location: URL?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if mode == .checking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let location {
                    Text("Expected CLIP resources at \(location.path)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 12)

            if mode != .checking {
                SettingsLink {
                    Label("Open AI Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var title: LocalizedStringResource {
        switch mode {
        case .checking:
            "Checking semantic-search capability…"

        case .unavailable:
            "Semantic search needs a valid CLIP model."

        case .failed:
            "Semantic search could not start."
        }
    }
}

struct SemanticSearchResultsHeaderView: View {
    let summary: RawCullSemanticSearchResultSummary
    let onSetShowsAllResults: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SemanticSearchResultsSummaryView(summary: summary)

            Spacer(minLength: 12)

            SemanticSearchResultActionsView(
                summary: summary,
                onSetShowsAllResults: onSetShowsAllResults,
            )
        }
    }
}

private struct SemanticSearchResultsSummaryView: View {
    let summary: RawCullSemanticSearchResultSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                "\(summary.resultCount) shown for “\(summary.query)”",
                comment: "Visible semantic-search result count followed by the user's query.",
            )
            .font(.callout.weight(.semibold))

            Text(
                "\(summary.rankedImageCount) images ranked. Results are relative CLIP similarity, not confidence.",
                comment: "Total scored images followed by a warning that the ranking is not a confidence value.",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SemanticSearchResultActionsView: View {
    let summary: RawCullSemanticSearchResultSummary
    let onSetShowsAllResults: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if summary.hiddenRankedImageCount > 0 {
                Button {
                    onSetShowsAllResults(true)
                } label: {
                    Text(
                        "Show All \(summary.rankedImageCount)",
                        comment: "Button that expands semantic search to every ranked image.",
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Shows lower-ranked images without running CLIP again.")
            } else if summary.rankedImageCount > RawCullSemanticSearchFeature.defaultResultLimit {
                Button {
                    onSetShowsAllResults(false)
                } label: {
                    Text(
                        "Show Top \(RawCullSemanticSearchFeature.defaultResultLimit)",
                        comment: "Button that limits semantic search to the highest-ranked images.",
                    )
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Hides lower-ranked images without running CLIP again.")
            }
        }
    }
}

struct SemanticSearchSearchingView: View {
    let query: String
    let progress: RawCullSemanticSearchProgress?

    var body: some View {
        ContentUnavailableView {
            Label("Searching", systemImage: "text.magnifyingglass")
        } description: {
            SemanticSearchLiveStatusView(
                query: query,
                progress: progress,
            )
        } actions: {
            ProgressView()
                .controlSize(.small)
        }
    }
}

private struct SemanticSearchLiveStatusView: View {
    let query: String
    let progress: RawCullSemanticSearchProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Text sent to CLIP") {
                Text(query)
                    .textSelection(.enabled)
            }

            switch progress {
            case let .encodingText(_, candidateCount):
                Label(
                    "Encoding the literal query before comparing \(candidateCount) cached image vectors.",
                    systemImage: "textformat.abc",
                )

            case let .scoring(_, completedCount, candidateCount):
                ProgressView(
                    value: Double(completedCount),
                    total: Double(max(1, candidateCount)),
                ) {
                    Text(
                        "Scored \(completedCount) of \(candidateCount) images",
                        comment: "Live semantic-search scoring progress.",
                    )
                }

            case nil:
                Text("Preparing the literal query for CLIP.")
            }

            Text(
                """
                CLIP does not extract words or tags during indexing. It \
                compares this text vector with cached image vectors and ranks \
                the closest matches.
                """,
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

struct SemanticSearchEmptyResultsView: View {
    let summary: RawCullSemanticSearchResultSummary

    var body: some View {
        ContentUnavailableView {
            Label("No Search Results", systemImage: "photo.badge.magnifyingglass")
        } description: {
            if summary.scoringFailureCount > 0 {
                Text(
                    "No indexed image could be scored for “\(summary.query)”. \(summary.scoringFailureCount) cached artifacts failed.",
                    comment: "Empty semantic-search result explanation followed by a failed artifact count.",
                )
            } else {
                Text("No indexed image matched the current catalog filters for “\(summary.query)”.")
            }
        }
    }
}

struct SemanticSearchEmptyIndexView: View {
    let excludedFileCount: Int
    let canIndex: Bool
    let isIndexing: Bool
    let onIndex: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Similarity Index Needed", systemImage: "externaldrive.badge.questionmark")
        } description: {
            Text(
                "\(excludedFileCount) images have no compatible CLIP artifact. Index Similarity to make them searchable.",
                comment: "Semantic-search empty-index explanation beginning with the number of excluded images.",
            )
        } actions: {
            if isIndexing {
                ProgressView("Indexing Similarity…")
                    .controlSize(.small)
            } else if canIndex {
                Button("Index Similarity", action: onIndex)
                    .buttonStyle(.borderedProminent)
            } else {
                SettingsLink {
                    Label("Open AI Settings", systemImage: "gear")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

struct SemanticSearchFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Search Failed", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
    }
}
