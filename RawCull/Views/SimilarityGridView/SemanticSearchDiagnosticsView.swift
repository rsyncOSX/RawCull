//
//  SemanticSearchDiagnosticsView.swift
//  RawCull
//
//  Exact runtime and score details for one completed CLIP text query.
//

import Foundation
import SwiftUI

struct SemanticSearchDiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss

    let diagnostics: RawCullSemanticSearchDiagnostics

    var body: some View {
        NavigationStack {
            List {
                SemanticSearchDiagnosticsQuerySection(
                    query: diagnostics.query,
                )
                SemanticSearchDiagnosticsRuntimeSection(
                    diagnostics: diagnostics,
                )
                SemanticSearchDiagnosticsScoreSection(
                    diagnostics: diagnostics,
                )
                SemanticSearchDiagnosticsResultsSection(
                    results: diagnostics.results,
                )
            }
            .navigationTitle("CLIP Search Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 680, minHeight: 620)
    }
}

private struct SemanticSearchDiagnosticsQuerySection: View {
    let query: String

    var body: some View {
        Section("What CLIP processed") {
            LabeledContent("Literal text query") {
                Text(query)
                    .textSelection(.enabled)
            }

            Text(
                """
                RawCull did not add prompt text, inspect filenames, or ask \
                CLIP to produce tags. CLIP encoded the literal query and \
                compared it with each compatible cached image vector.
                """,
            )
            .font(.callout)

            Text(
                """
                Cosine similarity is a relative ranking signal, not a \
                probability or confidence score. When no image matches the \
                query, CLIP still produces a least-bad ordering.
                """,
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct SemanticSearchDiagnosticsRuntimeSection: View {
    let diagnostics: RawCullSemanticSearchDiagnostics

    var body: some View {
        Section("Runtime") {
            LabeledContent(
                "Prompt policy",
                value: diagnostics.promptPolicyVersion,
            )
            LabeledContent(
                "Embedding dimensions",
                value: diagnostics.textEmbeddingDescriptor.dimensions.formatted(),
            )
            LabeledContent(
                "Tokenizer",
                value: diagnostics.textEmbeddingDescriptor.tokenizerVersion,
            )
            LabeledContent(
                "Compatible artifacts",
                value: diagnostics.compatibleArtifactCount.formatted(),
            )
            LabeledContent(
                "Incompatible artifacts",
                value: diagnostics.incompatibleArtifactCount.formatted(),
            )
            LabeledContent(
                "Scoring failures",
                value: diagnostics.scoringFailureCount.formatted(),
            )
            LabeledContent("Elapsed") {
                Text(
                    "\(diagnostics.durationMilliseconds) ms",
                    comment: "Semantic-search runtime in milliseconds.",
                )
                .monospacedDigit()
            }
            LabeledContent("Model fingerprint") {
                Text(diagnostics.backendDescriptor.modelFingerprint)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SemanticSearchDiagnosticsScoreSection: View {
    let diagnostics: RawCullSemanticSearchDiagnostics

    var body: some View {
        Section("Raw cosine score summary") {
            diagnosticScore("Highest", diagnostics.highestScore)
            diagnosticScore("Median", diagnostics.medianScore)
            diagnosticScore("Lowest", diagnostics.lowestScore)
            diagnosticScore("Full spread", diagnostics.scoreSpread)
            diagnosticScore("Gap between #1 and #2", diagnostics.topScoreGap)
        }
    }

    private func diagnosticScore(
        _ label: LocalizedStringResource,
        _ score: Float?,
    ) -> some View {
        LabeledContent(label) {
            if let score {
                Text(
                    score,
                    format: .number.precision(.fractionLength(4)),
                )
                .monospacedDigit()
            } else {
                Text("Not available")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SemanticSearchDiagnosticsResultsSection: View {
    let results: [RawCullSemanticSearchDiagnosticResult]

    var body: some View {
        Section("Every scored image") {
            ForEach(results) { result in
                SemanticSearchDiagnosticResultRow(result: result)
            }
        }
    }
}

private struct SemanticSearchDiagnosticResultRow: View {
    let result: RawCullSemanticSearchDiagnosticResult

    var body: some View {
        HStack(spacing: 12) {
            Text("#\(result.rank)")
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(minWidth: 42, alignment: .trailing)

            Text(result.fileName)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            Text(
                result.score,
                format: .number.precision(.fractionLength(4)),
            )
            .font(.callout.monospacedDigit())
            .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let score = result.score.formatted(
            .number.precision(.fractionLength(4)),
        )
        return "Rank \(result.rank), \(result.fileName), raw cosine similarity \(score)"
    }
}
