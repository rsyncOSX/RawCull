//
//  SimilarityControlsView.swift
//  RawCull
//

import SwiftUI

struct SimilarityControlsView: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        // Index button — compute embeddings for all catalog files
        Button {
            Task { await viewModel.indexSimilarity() }
        } label: {
            if viewModel.similarityModel.isIndexing {
                Label("Indexing…", systemImage: "wand.and.sparkles")
            } else if viewModel.similarityModel.embeddings.isEmpty {
                Label("Index Similarity", systemImage: "wand.and.sparkles")
            } else {
                Label("Re-index", systemImage: "wand.and.sparkles")
            }
        }
        .font(.caption)
        .disabled(viewModel.similarityModel.isIndexing || viewModel.files.isEmpty)
        .help("Compute visual feature embeddings for all images in this catalog")

        // Cancel button — only visible while indexing
        if viewModel.similarityModel.isIndexing {
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

        // Find Similar button — enabled when an image is selected and embeddings exist
        if !viewModel.similarityModel.embeddings.isEmpty, !viewModel.similarityModel.isIndexing {
            Button {
                Task { await viewModel.findSimilarToSelected() }
            } label: {
                Label("Find Similar", systemImage: "photo.stack")
            }
            .font(.caption)
            .disabled(viewModel.selectedFile == nil)
            .help("Rank all images by visual similarity to the selected image")

            // Sort toggle — visible once distances have been computed
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
        }
    }
}
