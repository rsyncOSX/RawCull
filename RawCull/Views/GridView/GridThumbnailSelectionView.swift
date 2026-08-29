//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//
//  Thin wrapper over `CullingGridView` that supplies the sharpness-controls
//  header (hidden while burst grouping is active).
//

import AppKit
import SwiftUI

struct GridThumbnailSelectionView: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        CullingGridView(
            viewModel: viewModel,
            similarityFeature: similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
        ) {
            if !viewModel.showsBurstGroups {
                SharpnessControlsView(
                    viewModel: viewModel,
                    similarityFeature: similarityFeature,
                )
            }
        }
    }
}
