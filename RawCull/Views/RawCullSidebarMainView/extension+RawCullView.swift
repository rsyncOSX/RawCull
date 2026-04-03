//
//  extension+RawCullView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension RawCullMainView {
    var toolbarContent: some ToolbarContent {
        SharedMainToolbarContent(
            viewModel: viewModel,
            isHorizontal: false,
            toggleLayout: toggleshowvertical,
            toggleInspector: toggleShowInspector,
            openGridThumbnail: openGridThumbnailWindow,
        )
    }

    func toggleShowInspector() {
        viewModel.hideInspector.toggle()
    }

    func toggleshowvertical() {
        showhorizontalthumbnailview.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        showGridThumbnail = true
    }

    func handleToggleSelection(for file: FileItem) {
        Task {
            viewModel.selectFile(file)
            await viewModel.toggleTag(for: file)
        }
    }

    func handlePickerResult(_ result: Result<URL, Error>) {
        if case let .success(url) = result {
            if url.startAccessingSecurityScopedResource() {
                // Track so stopAccessingSecurityScopedResource() is called
                // when the source is removed or the app terminates.
                viewModel.trackSecurityScopedAccess(for: url)
                let source = ARWSourceCatalog(name: url.lastPathComponent, url: url)
                viewModel.sources.append(source)
                viewModel.selectedSource = source
            }
        }
    }

    func extractAllJPGS() {
        Task {
            // Using the same property to start the progressview.
            // The text in the Progress is computed to check which
            // of the current..Actor is != nil
            viewModel.creatingthumbnails = true

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: viewModel.fileHandler,
                maxfilesHandler: viewModel.maxfilesHandler,
                estimatedTimeHandler: viewModel.estimatedTimeHandler,
                memorypressurewarning: { _ in },
            )

            let extract = ExtractAndSaveJPGs()
            await extract.setFileHandlers(handlers)
            viewModel.currentExtractAndSaveJPGsActor = extract

            guard let url = viewModel.selectedSource?.url else { return }
            await extract.extractAndSaveAlljpgs(from: url)

            viewModel.currentExtractAndSaveJPGsActor = nil // ← NEW: clean up
            viewModel.creatingthumbnails = false
        }
    }
}
