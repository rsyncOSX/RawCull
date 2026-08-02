//
//  SimilarityGridSelectionView.swift
//  RawCull
//
//  Similarity and burst-grouping home with category-based result browsing.
//

import AppKit
import SwiftUI

struct SimilarityGridSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var analyzeBurstsRequested: Bool = false
    @State private var pendingRegroupTask: Task<Void, Never>?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            SemanticSearchControlsView(viewModel: viewModel)

            Divider()

            switch viewModel.similarityModel.semanticSearchState {
            case .idle:
                OrdinarySimilarityWorkflowView(
                    viewModel: viewModel,
                    analyzeBurstsRequested: $analyzeBurstsRequested,
                    similarityThresholdChanged: scheduleBurstRegroup,
                )

            case let .searching(query):
                SemanticSearchSearchingView(
                    query: query,
                    progress: viewModel.similarityModel.semanticSearchProgress,
                )

            case let .results(summary) where summary.resultCount == 0:
                SemanticSearchEmptyResultsView(summary: summary)

            case let .results(summary):
                CullingGridView(viewModel: viewModel) {
                    SemanticSearchResultsHeaderView(
                        summary: summary,
                        diagnostics: viewModel.similarityModel.semanticSearchDiagnostics,
                        onSetShowsAllResults: { showsAll in
                            Task {
                                await viewModel.setSemanticSearchShowsAllResults(
                                    showsAll,
                                )
                            }
                        },
                    )
                }

            case let .emptyIndex(_, excludedFileCount):
                SemanticSearchEmptyIndexView(
                    excludedFileCount: excludedFileCount,
                    canIndex: viewModel.similarityModel.canIndexSemanticSearchArtifacts,
                    isIndexing: viewModel.similarityModel.isIndexing
                        && viewModel.similarityModel.canIndexSemanticSearchArtifacts,
                    onIndex: {
                        Task {
                            await viewModel.indexSimilarity()
                        }
                    },
                )

            case let .failed(_, message):
                SemanticSearchFailureView(message: message)
            }
        }
    }

    private func scheduleBurstRegroup() {
        pendingRegroupTask?.cancel()
        pendingRegroupTask = Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled {
                return
            }
            await viewModel.reGroupBursts()
        }
    }
}

private struct OrdinarySimilarityWorkflowView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var analyzeBurstsRequested: Bool
    let similarityThresholdChanged: () -> Void

    var body: some View {
        if viewModel.similarityModel.burstModeActive {
            CullingGridView(viewModel: viewModel) {
                BurstGroupHeaderControlsView(
                    viewModel: viewModel,
                    similarityThresholdChanged: similarityThresholdChanged,
                )
            }
        } else {
            BurstGroupsHomeView(
                viewModel: viewModel,
                analyzeBurstsRequested: $analyzeBurstsRequested,
                similarityThresholdChanged: similarityThresholdChanged,
            )
        }
    }
}

private struct BurstGroupHeaderControlsView: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityThresholdChanged: () -> Void

    var body: some View {
        let sensitivity = viewModel.similarityModel.burstSensitivity.formatted(
            .number.precision(.fractionLength(2)),
        )
        let groupCount = viewModel.similarityModel.burstGroups.count

        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Similarity")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Slider(
                    value: $viewModel.similarityModel.burstSensitivity,
                    in: 0.05 ... 0.60,
                )
                .frame(width: 120)
                .help("Burst sensitivity — lower = tighter groups, higher = similar scenes grouped together")
                .onChange(of: viewModel.similarityModel.burstSensitivity) {
                    similarityThresholdChanged()
                }

                Text(
                    "\(sensitivity) · \(groupCount) groups",
                    comment: "Burst sensitivity value followed by the number of groups.",
                )
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 84, alignment: .leading)
            }

            Spacer(minLength: 8)

            if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
                HStack {
                    ProgressView()
                    Text("Calibrating focus-mask threshold, please wait...")
                }
            }
        }
    }
}
