//
//  SimilarityGridSelectionView.swift
//  RawCull
//
//  Similarity-focused grid. Header exposes similarity indexing, burst grouping,
//  and the automatic sharpness-scoring prerequisite toggle.
//

import AppKit
import SwiftUI

struct SimilarityGridSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var autoSharpnessScoring: Bool = true
    @State private var analyzeBurstsRequested: Bool = false

    /// Debounced regroup task for the burst-sensitivity slider — mirrors
    /// SimilarityControlsView so dragging the slider collapses to a single
    /// regroup call ~200 ms after the drag stops.
    @State private var pendingRegroupTask: Task<Void, Never>?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        CullingGridView(viewModel: viewModel) {
            similarityHeaderControls
        }
    }

    // MARK: - Inline similarity controls (with auto-scoring prerequisite)

    @ViewBuilder
    private var similarityHeaderControls: some View {
        let hasEmbeddings = !viewModel.similarityModel.embeddings.isEmpty
        let isIndexing = viewModel.similarityModel.isIndexing
        let isGrouping = viewModel.similarityModel.isGrouping
        let burstAnalysisIsBusy = analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
        let inBurstMode = viewModel.similarityModel.burstModeActive
        let sharpnessControlsDisabled = viewModel.sharpnessModel.isScoring || isIndexing || isGrouping || burstAnalysisIsBusy
        let reviewCounts = viewModel.burstReviewQueueCounts

        if !inBurstMode {
            SharpnessIntentControlsView(
                viewModel: viewModel,
                isDisabled: sharpnessControlsDisabled,
                showsParametersButton: true,
                style: .compactInfo,
            )

            Divider().frame(height: 16)

            Button {
                runWithAutoScoring { await viewModel.indexSimilarity() }
            } label: {
                if isIndexing {
                    Label("Indexing…", systemImage: "wand.and.sparkles")
                } else if hasEmbeddings {
                    Label("Re-index", systemImage: "wand.and.sparkles")
                } else {
                    Label("Index Similarity", systemImage: "wand.and.sparkles")
                }
            }
            .font(.caption)
            .disabled(isIndexing || burstAnalysisIsBusy || viewModel.files.isEmpty)
            .help("Compute visual feature embeddings for all images in this catalog")

            if isIndexing {
                Button(role: .cancel) {
                    viewModel.similarityModel.cancelIndexing()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .font(.caption)
                .tint(.red)
                .help("Abort similarity indexing and discard partial results")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if hasEmbeddings, !isIndexing {
                Button {
                    runWithAutoScoring { await viewModel.findSimilarToSelected() }
                } label: {
                    Label("Find Similar", systemImage: "photo.stack")
                }
                .font(.caption)
                .disabled(viewModel.selectedFile == nil)
                .help("Rank all images by visual similarity to the selected image")

                if !viewModel.similarityModel.distances.isEmpty {
                    Toggle(isOn: $viewModel.similarityModel.sortBySimilarity) {
                        Label("Similarity", systemImage: "arrow.up.arrow.down")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                    .help("Sort thumbnails by similarity to selected image (most similar first)")
                    .onChange(of: viewModel.similarityModel.sortBySimilarity) { _, _ in
                        Task(priority: .background) {
                            await viewModel.handleSortOrderChange()
                        }
                    }
                }

                Divider().frame(height: 16)
            }
        }

        if !isIndexing {
            if inBurstMode {
                SharpnessIntentControlsView(
                    viewModel: viewModel,
                    isDisabled: sharpnessControlsDisabled,
                    showsParametersButton: true,
                    style: .compactInfo,
                )

                Divider().frame(height: 16)

                HStack(spacing: 4) {
                    Slider(
                        value: $viewModel.similarityModel.burstSensitivity,
                        in: 0.05 ... 0.60,
                    )
                    .frame(width: 70)
                    .help("Burst sensitivity — lower = tighter groups, higher = similar scenes grouped together")
                    .onChange(of: viewModel.similarityModel.burstSensitivity) { _, _ in
                        pendingRegroupTask?.cancel()
                        pendingRegroupTask = Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            if Task.isCancelled { return }
                            await viewModel.reGroupBursts()
                        }
                    }
                    Text(
                        String(
                            format: "%.2f · %d groups",
                            viewModel.similarityModel.burstSensitivity,
                            viewModel.similarityModel.burstGroups.count,
                        ),
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                }

                Picker("Review Queue", selection: $viewModel.burstReviewQueueFilter) {
                    ForEach(BurstReviewQueueFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 270)
                .disabled(viewModel.burstAnalysisResults.isEmpty)
                .help("Filter burst groups by review state")

                Text("\(reviewCounts.needsReview) review · \(reviewCounts.deferred) deferred · \(reviewCounts.reviewed) done")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 170, alignment: .leading)

                Button {
                    viewModel.similarityModel.burstModeActive = false
                    viewModel.burstReviewQueueFilter = .all
                } label: {
                    Label("Exit Groups", systemImage: "xmark.circle")
                }
                .font(.caption)
                .help("Return to flat grid view")

                Button {
                    analyzeBurstsRequested = true
                    Task {
                        defer { analyzeBurstsRequested = false }
                        await viewModel.reindexBurstAnalysis()
                    }
                } label: {
                    Label("Reanalyze Bursts", systemImage: "arrow.clockwise")
                }
                .font(.caption)
                .disabled(isGrouping || burstAnalysisIsBusy || viewModel.files.isEmpty)
                .help("Delete saved burst analysis for this catalog and recompute from scratch")
            } else {
                Toggle(isOn: $autoSharpnessScoring) {
                    Label("Auto Sharpness", systemImage: "scope")
                }
                .toggleStyle(.button)
                .font(.caption)
                .disabled(sharpnessControlsDisabled)
                .help("Auto-run sharpness scoring before similarity actions when scores are missing")

                Button {
                    analyzeBurstsRequested = true
                    Task {
                        defer { analyzeBurstsRequested = false }
                        await viewModel.analyzeBursts()
                    }
                } label: {
                    if isGrouping {
                        Label("Grouping…", systemImage: "square.stack.3d.up")
                    } else if hasEmbeddings {
                        Label("Analyze Bursts", systemImage: "square.stack.3d.up")
                    } else {
                        Label("Analyze Bursts", systemImage: "square.stack.3d.up")
                    }
                }
                .font(.caption)
                .disabled(isGrouping || burstAnalysisIsBusy || viewModel.files.isEmpty)
                .help("Group burst sequences and recommend best frames")

                if reviewCounts.needsReview > 0 {
                    Button {
                        viewModel.similarityModel.burstModeActive = true
                        viewModel.burstReviewQueueFilter = .needsReview
                    } label: {
                        Label("\(reviewCounts.needsReview) Need Review", systemImage: "tray.full")
                    }
                    .font(.caption)
                    .help("Show burst groups that need review")
                }
            }
        }

        // Spinner shown while calibrating is in progress
        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating focus-mask threshold, please wait...")
            }
        }
    }

    /// Runs `action` after first computing sharpness scores when the toggle
    /// is on and scores are missing. If scoring is already in flight,
    /// `scoreFiles` awaits the existing task, so rapid actions cannot bypass
    /// the prerequisite.
    private func runWithAutoScoring(_ action: @escaping @MainActor () async -> Void) {
        Task {
            if autoSharpnessScoring, viewModel.sharpnessModel.scores.isEmpty {
                await viewModel.calibrateAndScoreCurrentCatalog()
            }
            await action()
        }
    }
}
