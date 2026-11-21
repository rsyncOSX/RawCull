//
//  SharpnessControlsView.swift
//  RawCull
//
//  Created by Thomas Evensen on 10/04/2026.
//

import SwiftUI

struct SharpnessControlsView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(CatalogController.self) private var catalogController
    @Environment(SelectionModel.self) private var selection
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    let similarityFeature: RawCullSimilarityFeature
    @State private var isShowingCLIPIndexConfirmation = false
    @State private var preservesSimilarityOrderOnDisable = false

    var body: some View {
        // Score button — calibrates from the burst then scores
        Button {
            Task { await catalogController.calibrateAndScoreCurrentCatalog() }
        } label: {
            if sharpnessModel.isScoring {
                Label("Scoring…", systemImage: "scope")
            } else if sharpnessModel.afPointScores.isEmpty {
                Label("Score AF Sharpness", systemImage: "scope")
            } else {
                Label("Re-score", systemImage: "scope")
            }
        }
        .font(.caption)
        .disabled(sharpnessModel.isScoring || catalogController.sharpnessScoringTargetCount == 0)
        .help("Measure detail around the recorded AF point for \(catalogController.sharpnessScoringTargetDescription). Photos without usable AF detail sort last.")

        // Cancel button — only visible while scoring
        if sharpnessModel.isScoring {
            Button(role: .cancel) {
                sharpnessModel.cancelScoring()
            } label: {
                Label("Cancel", systemImage: "xmark.circle")
            }
            .font(.caption)
            .tint(.red)
            .help("Abort sharpness scoring and discard results")
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }

        // Sort toggle — requires an actual AF measurement. Legacy combined scores cannot rank AF detail.
        if !sharpnessModel.afPointScores.isEmpty, !sharpnessModel.isScoring {
            Toggle(isOn: Bindable(sharpnessModel).sortBySharpness) {
                Label("AF-point sharpness", systemImage: "arrow.up.arrow.down")
            }
            .toggleStyle(.button)
            .font(.caption)
            .help(
                sharpnessModel.sortBySharpness
                    ? "Stop sorting by AF-point sharpness"
                    : "Sort by detail at the AF point, strongest first. Unknown measurements sort last.",
            )
            .onChange(of: sharpnessModel.sortBySharpness) { _, isEnabled in
                if isEnabled {
                    similarityFeature.setSimilaritySortingActive(false)
                } else if similarityFeature.isSimilaritySortingActive {
                    return
                }
                Task(priority: .background) {
                    await catalogController.handleSharpnessSortingChange(isEnabled: isEnabled)
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
            (catalog.file(withID: selection.selectedFileID) == nil
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
                sharpnessModel.sortBySharpness = false
                Task { await catalogController.findSimilarToSelected() }
            } else if preservesSimilarityOrderOnDisable {
                preservesSimilarityOrderOnDisable = false
            } else if !sharpnessModel.sortBySharpness {
                Task(priority: .background) {
                    await catalogController.handleSortOrderChange()
                }
            }
        }
        .onChange(of: selection.selectedFileID) { oldID, newID in
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
        if sharpnessModel.isCalibratingSharpnessScoring {
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
        !similarityFeature.hasCompleteIndex(for: catalog.files)
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
