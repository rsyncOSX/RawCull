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
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewController: DeepAIReviewController

    // Periphery 3.8 does not follow projected-value reads from SDK 27's macro-backed @State.
    // periphery:ignore
    @State private var analyzeBurstsRequested: Bool = false
    @State private var pendingRegroupTask: Task<Void, Never>?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            SemanticSearchControlsView(
                semanticSearchFeature: semanticSearchFeature,
                similarityFeature: similarityFeature,
            )

            Divider()

            switch semanticSearchFeature.state {
            case .idle:
                OrdinarySimilarityWorkflowView(
                    viewModel: viewModel,
                    similarityFeature: similarityFeature,
                    semanticSearchFeature: semanticSearchFeature,
                    deepAIReviewController: deepAIReviewController,
                    analyzeBurstsRequested: $analyzeBurstsRequested,
                    similarityThresholdChanged: scheduleBurstRegroup,
                )

            case let .searching(query):
                SemanticSearchSearchingView(
                    query: query,
                    progress: semanticSearchFeature.progress,
                )

            case let .results(summary) where summary.resultCount == 0:
                SemanticSearchEmptyResultsView(summary: summary)

            case let .results(summary):
                CullingGridView(
                    viewModel: viewModel,
                    similarityFeature: similarityFeature,
                    semanticSearchFeature: semanticSearchFeature,
                    deepAIReviewController: deepAIReviewController,
                ) {
                    SemanticSearchResultsHeaderView(
                        summary: summary,
                        onSetShowsAllResults: { showsAll in
                            Task {
                                await semanticSearchFeature.setShowsAllResults(showsAll)
                            }
                        },
                    )
                }

            case let .emptyIndex(_, excludedFileCount):
                SemanticSearchEmptyIndexView(
                    excludedFileCount: excludedFileCount,
                    canIndex: semanticSearchFeature.canIndexArtifacts,
                    isIndexing: semanticSearchFeature.isIndexingCompatibleArtifacts,
                    onIndex: indexSimilarity,
                )

            case let .failed(_, message):
                SemanticSearchFailureView(message: message)
            }
        }
        .onDisappear {
            pendingRegroupTask?.cancel()
            pendingRegroupTask = nil
        }
    }

    private func indexSimilarity() {
        guard semanticSearchFeature.presentation.canStartIndexing else { return }
        Task {
            await similarityFeature.indexCurrentCatalog()
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
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let deepAIReviewController: DeepAIReviewController
    @Binding var analyzeBurstsRequested: Bool
    let similarityThresholdChanged: () -> Void

    var body: some View {
        if viewModel.similarityModel.burstModeActive {
            CullingGridView(
                viewModel: viewModel,
                similarityFeature: similarityFeature,
                semanticSearchFeature: semanticSearchFeature,
                deepAIReviewController: deepAIReviewController,
            ) {
                BurstGroupHeaderControlsView(
                    viewModel: viewModel,
                    similarityThresholdChanged: similarityThresholdChanged,
                )
            }
        } else {
            BurstGroupsHomeView(
                viewModel: viewModel,
                similarityFeature: similarityFeature,
                semanticSearchFeature: semanticSearchFeature,
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
        let groupCount = viewModel.burstReviewSummary.totalGroups

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
