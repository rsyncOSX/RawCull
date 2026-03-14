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
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: opentaggedGridThumbnailWindow) {
                Label("Grid Tagged Images", systemImage: "square.grid.2x2.fill")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || showGridtaggedThumbnailWindow() == false)
            .help("Open tagged thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowvertical) {
                Label("Vertical", systemImage: "arrow.left.and.right.text.vertical")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show Horizontal thumbnails")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowsavedfiles) {
                Label("Details", systemImage: "square.and.arrow.down")
            }
            .help("Show SavedFiles")
        }
    }

    func toggleshowsavedfiles() {
        showSavedFiles.toggle()
    }

    func toggleshowvertical() {
        showhorizontalvertical.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        openWindow(id: WindowIdentifier.gridThumbnails.rawValue)
    }

    func opentaggedGridThumbnailWindow() {
        openWindow(id: WindowIdentifier.gridTaggedThumbnails.rawValue)
    }

    private func showGridtaggedThumbnailWindow() -> Bool {
        guard let catalogURL = viewModel.selectedSource?.url,
              let index = viewModel.cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalogURL })
        else {
            return false
        }
        if let records = viewModel.cullingModel.savedFiles[index].filerecords {
            return !records.isEmpty
        }
        return false
    }

    func handleToggleSelection(for file: FileItem) {
        Task {
            await viewModel.cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name,
            )
        }
    }

    func handlePickerResult(_ result: Result<URL, Error>) {
        if case let .success(url) = result {
            // Security: Request persistent access
            if url.startAccessingSecurityScopedResource() {
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
