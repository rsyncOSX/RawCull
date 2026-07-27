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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(
                "\(summary.resultCount) results for “\(summary.query)”",
                comment: "Semantic-search result count followed by the user's query.",
            )
            .font(.callout.weight(.semibold))

            Text("Results are ordered by relative CLIP similarity, not confidence.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct SemanticSearchSearchingView: View {
    let query: String

    var body: some View {
        ContentUnavailableView {
            Label("Searching", systemImage: "text.magnifyingglass")
        } description: {
            Text("Ranking compatible cached images for “\(query)”.")
        } actions: {
            ProgressView()
                .controlSize(.small)
        }
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
