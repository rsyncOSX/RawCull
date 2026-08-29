//
//  SharpnessControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

struct SharpnessControlsView: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
    @State private var isShowingCLIPIndexConfirmation = false
    @State private var preservesSimilarityOrderOnDisable = false

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
                    similarityFeature.setSimilaritySortingActive(false)
                } else if similarityFeature.isSimilaritySortingActive {
                    return
                }
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        Toggle(isOn: similaritySortingBinding) {
            if similarityFeature.indexing.isIndexing {
                Label("Indexing \(similarityBackendName)…", systemImage: "photo.stack")
            } else if needsSimilarityIndex {
                Label("Index & Find Similar (\(similarityBackendName))", systemImage: "photo.stack")
            } else {
                Label("Find Similar (\(similarityBackendName))", systemImage: "photo.stack")
            }
        }
        .toggleStyle(.button)
        .font(.caption)
        .disabled(
            (viewModel.selectedFile == nil
                && !similarityFeature.isSimilaritySortingActive)
                || similarityFeature.indexing.isIndexing,
        )
        .help(similarityHelp)
        .confirmationDialog(
            "Index images with CLIP?",
            isPresented: $isShowingCLIPIndexConfirmation,
        ) {
            Button("Index & Find Similar") {
                similarityFeature.setSimilaritySortingActive(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("RawCull will build missing CLIP index entries before finding images similar to the selected image. This may take some time.")
        }
        .onChange(of: similarityFeature.isSimilaritySortingActive) { _, isEnabled in
            if isEnabled {
                viewModel.sharpnessModel.sortBySharpness = false
                Task { await viewModel.findSimilarToSelected() }
            } else if preservesSimilarityOrderOnDisable {
                preservesSimilarityOrderOnDisable = false
            } else if !viewModel.sharpnessModel.sortBySharpness {
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }
        .onChange(of: viewModel.selectedFileID) { oldID, newID in
            guard oldID != newID,
                  similarityFeature.isSimilaritySortingActive
            else { return }

            // A new selection prepares Find Similar for a new anchor while
            // preserving the currently displayed similarity ranking.
            preservesSimilarityOrderOnDisable = true
            similarityFeature.cancelRanking()
            similarityFeature.setSimilaritySortingActive(false)
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
        similarityFeature.backend.displayName
    }

    private var similaritySortingBinding: Binding<Bool> {
        Binding(
            get: { similarityFeature.isSimilaritySortingActive },
            set: { isEnabled in
                if isEnabled, needsSimilarityIndex, similarityBackendName == "CLIP" {
                    isShowingCLIPIndexConfirmation = true
                } else {
                    similarityFeature.setSimilaritySortingActive(isEnabled)
                }
            },
        )
    }

    private var needsSimilarityIndex: Bool {
        !similarityFeature.hasCompleteIndex(for: viewModel.files)
    }

    private var similarityHelp: String {
        if similarityFeature.indexing.isIndexing {
            return "Building the \(similarityBackendName) similarity index"
        }
        if similarityFeature.isSimilaritySortingActive {
            return "Stop sorting by similarity"
        }
        if needsSimilarityIndex {
            return "Build missing \(similarityBackendName) index entries, then rank images by similarity to the selected image"
        }
        return "Rank all images by \(similarityBackendName) similarity to the selected image"
    }
}
