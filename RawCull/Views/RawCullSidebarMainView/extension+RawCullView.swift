//
//  extension+RawCullView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import SwiftUI

extension RawCullMainView {
    var toolbarContent: some ToolbarContent {
        SharedMainToolbarContent(
            catalog: viewModel.catalog,
            selection: viewModel.selection,
            ratings: viewModel.ratings,
            presentation: viewModel.presentation,
            burstWorkflow: viewModel.burstWorkflow,
            navigation: viewModel.navigation,
            catalogController: viewModel.catalogController,
            sharpnessModel: viewModel.sharpnessModel,
            similarityFeature: viewModel.similarityFeature,
            semanticSearchFeature: semanticSearchFeature,
            isDisabled: toolbarIsDisabled,
            toggleMetadataPanel: toggleLoupeMetadataPanel,
        )
    }

    func toggleLoupeMetadataPanel() {
        guard viewModel.navigation.mainViewMode == .loupe else { return }
        withAnimation(.snappy) {
            viewModel.presentation.showsLoupeMetadataPanel.toggle()
        }
    }

    func handlePickerResult(_ result: Result<URL, Error>) {
        viewModel.presentation.isShowingPicker = false

        if case let .success(url) = result {
            let source = ARWSourceCatalog(name: url.lastPathComponent, url: url)
            viewModel.catalog.sources.append(source)
            viewModel.catalog.selectedSource = source
        }
    }
}
