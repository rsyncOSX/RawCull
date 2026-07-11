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
            viewModel: viewModel,
            toggleInspector: toggleShowInspector,
        )
    }

    func toggleShowInspector() {
        viewModel.hideInspector.toggle()
    }

    func handlePickerResult(_ result: Result<URL, Error>) {
        viewModel.isShowingPicker = false

        if case let .success(url) = result {
            let source = ARWSourceCatalog(name: url.lastPathComponent, url: url)
            viewModel.sources.append(source)
            viewModel.selectedSource = source
        }
    }
}
