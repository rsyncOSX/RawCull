//
//  SimilarityControlsView.swift
//  RawCull
//

import SwiftUI

struct SimilarityControlsView: View {
    @Bindable var viewModel: RawCullViewModel

    /// Debounced regrouping trigger. Cancelled and recreated on every slider
    /// tick so continuous dragging collapses to a single regroup call ~200 ms
    /// after the drag stops.
    @State private var pendingRegroupTask: Task<Void, Never>?

    var body: some View {
        let hasEmbeddings = !viewModel.similarityModel.embeddings.isEmpty
        let isIndexing = viewModel.similarityModel.isIndexing
        let isGrouping = viewModel.similarityModel.isGrouping
        let inBurstMode = viewModel.similarityModel.burstModeActive

        // ── Classic index button + similarity controls (hidden in burst mode) ──
        if !inBurstMode {
            Button {
                Task { await viewModel.indexSimilarity() }
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
            .disabled(isIndexing || viewModel.files.isEmpty)
            .help("Compute visual feature embeddings for all images in this catalog")

            // Cancel indexing
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

            // ── Anchor-based similarity (post-index) ──────────────────────────
            if hasEmbeddings, !isIndexing {
                Button {
                    Task { await viewModel.findSimilarToSelected() }
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

        // ── Burst grouping ────────────────────────────────────────────────────
        if !isIndexing {
            if inBurstMode {
                // Sensitivity slider + live group count
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

                Button {
                    viewModel.similarityModel.burstModeActive = false
                } label: {
                    Label("Exit Groups", systemImage: "xmark.circle")
                }
                .font(.caption)
                .help("Return to flat grid view")
            } else {
                Button {
                    Task { await viewModel.indexAndGroupBursts() }
                } label: {
                    if isGrouping {
                        Label("Grouping…", systemImage: "square.stack.3d.up")
                    } else if hasEmbeddings {
                        Label("Group Bursts", systemImage: "square.stack.3d.up")
                    } else {
                        Label("Index + Group Bursts", systemImage: "square.stack.3d.up")
                    }
                }
                .font(.caption)
                .disabled(isGrouping || viewModel.files.isEmpty)
                .help(
                    hasEmbeddings
                        ? "Cluster consecutive similar frames into burst groups"
                        : "Index all images then cluster into burst groups",
                )
            }
        }
    }
}
