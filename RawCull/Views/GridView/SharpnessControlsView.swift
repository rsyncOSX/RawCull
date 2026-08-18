//
//  SharpnessControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

struct SharpnessControlsView: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        // Score button — calibrates from the burst then scores
        Button {
            Task { await viewModel.calibrateAndScoreCurrentCatalog() }
        } label: {
            if viewModel.sharpnessModel.isScoring {
                Label("Scoring…", systemImage: "scope")
            } else if viewModel.sharpnessModel.scores.isEmpty {
                Label("Score Sharpness", systemImage: "scope")
            } else {
                Label("Re-score", systemImage: "scope")
            }
        }
        .font(.caption)
        .disabled(viewModel.sharpnessModel.isScoring || viewModel.sharpnessScoringTargetFiles.isEmpty)
        .help("Calibrate the visual edge threshold, then score selected thumbnails, the active star filter, or the full catalog (\(viewModel.sharpnessScoringTargetDescription))")

        // Cancel button — only visible while scoring
        if viewModel.sharpnessModel.isScoring {
            Button(role: .cancel) {
                viewModel.sharpnessModel.cancelScoring()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .font(.caption)
            .tint(.red)
            .help("Abort sharpness scoring and discard results")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Sort toggle — only visible once scores exist and not currently scoring
        if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
            Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                Label("Sharpness", systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .font(.caption)
            .help(
                viewModel.sharpnessModel.sortBySharpness
                    ? "Stop sorting by sharpness"
                    : "Sort thumbnails sharpest-first",
            )
            .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, isEnabled in
                if isEnabled {
                    viewModel.similarityModel.sortBySimilarity = false
                } else if viewModel.similarityModel.sortBySimilarity {
                    return
                }
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        Toggle(isOn: $viewModel.similarityModel.sortBySimilarity) {
            Label("Find Similar (\(similarityBackendName))", systemImage: "photo.stack")
        }
        .toggleStyle(.button)
        .font(.caption)
        .disabled(
            viewModel.selectedFile == nil
                && !viewModel.similarityModel.sortBySimilarity
                && !viewModel.hasCompletedBurstAnalysis,
        )
        .help(
            viewModel.similarityModel.sortBySimilarity
                ? "Stop sorting by similarity"
                : "Rank all images by \(similarityBackendName) similarity to the selected image",
        )
        .onChange(of: viewModel.similarityModel.sortBySimilarity) { _, isEnabled in
            if isEnabled {
                viewModel.sharpnessModel.sortBySharpness = false
                Task { await viewModel.findSimilarToSelected() }
            } else if !viewModel.sharpnessModel.sortBySharpness {
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
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

    private var similarityBackendName: String {
        viewModel.similarityModel.backendDescriptor.backend == "clip"
            ? "CLIP"
            : "Vision"
    }
}
