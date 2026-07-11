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
        if viewModel.similarityModel.burstModeActive {
            CullingGridView(viewModel: viewModel) {
                burstGroupHeaderControls
            }
        } else {
            BurstGroupsHomeView(
                viewModel: viewModel,
                analyzeBurstsRequested: $analyzeBurstsRequested,
            )
        }
    }

    @ViewBuilder
    private var burstGroupHeaderControls: some View {
        let isIndexing = viewModel.similarityModel.isIndexing
        let isGrouping = viewModel.similarityModel.isGrouping
        let burstAnalysisIsBusy = analyzeBurstsRequested || viewModel.burstAnalysisProgress.isRunning
        let sharpnessControlsDisabled = viewModel.sharpnessModel.isScoring
            || isIndexing
            || isGrouping
            || burstAnalysisIsBusy

        Text("Scoring in Scoring Parameters.")
            .font(.caption)
            .foregroundStyle(.secondary)

        Button {
            viewModel.activeSheet = .scoringParams
        } label: {
            Label("Scoring Parameters", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.bordered)
        .disabled(sharpnessControlsDisabled)

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
            .onChange(of: viewModel.similarityModel.burstSensitivity) { _, _ in
                pendingRegroupTask?.cancel()
                pendingRegroupTask = Task {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    if Task.isCancelled {
                        return
                    }
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
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 84, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.7), in: .capsule)

        Spacer(minLength: 8)

        Button {
            viewModel.similarityModel.burstModeActive = false
            viewModel.burstReviewQueueFilter = .all
        } label: {
            Label("Exit Groups", systemImage: "xmark.circle")
        }
        .buttonStyle(.bordered)
        .help("Return to the burst groups home")

        Button {
            analyzeBurstsRequested = true
            Task {
                defer { analyzeBurstsRequested = false }
                await viewModel.analyzeBursts()
            }
        } label: {
            Label("Reanalyze Bursts", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.bordered)
        .disabled(sharpnessControlsDisabled)

        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating focus-mask threshold, please wait...")
            }
        }
    }
}
