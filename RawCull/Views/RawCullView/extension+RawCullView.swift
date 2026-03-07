//
//  extension+RawCullView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI
import UniformTypeIdentifiers

extension RawCullView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        // Zoom controls - only visible when a file is selected
        if viewModel.selectedFile != nil {
            ToolbarItem(placement: .secondaryAction) {
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.scale = max(0.5, viewModel.scale - 0.2)
                    }
                }, label: {
                    Image(systemName: "minus")
                        .font(.system(size: 12))
                })
                .disabled(viewModel.scale <= 0.5)
                .help("Zoom out")
            }

            ToolbarItem(placement: .secondaryAction) {
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.resetZoom()
                    }
                }, label: {
                    Text("Reset \(String(format: "%.0f%%", viewModel.scale * 100))")
                        .font(.caption)
                })
                .disabled(viewModel.scale == 1.0 && viewModel.offset == .zero)
                .help("Reset zoom")
            }

            ToolbarItem(placement: .secondaryAction) {
                Button(action: {
                    withAnimation(.spring()) {
                        viewModel.scale = min(4.0, viewModel.scale + 0.2)
                    }
                }, label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                })
                .disabled(viewModel.scale >= 4.0)
                .help("Zoom in")
            }
        }

        ToolbarItem(placement: .navigation) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .navigation) {
            Button(action: toggleshowdetailonly) {
                Label("Details", systemImage: "photo")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show details")
        }
    }

    func toggleshowdetailonly() {
        showDetailOnly.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            viewModel: viewModel,
            cullingManager: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles
        )
        openWindow(id: WindowIdentifier.gridThumbnails.rawValue)
    }

    func handleToggleSelection(for file: FileItem) {
        Task {
            await viewModel.cullingModel.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name
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
            viewModel.creatingthumbnails = true

            let handlers = CreateFileHandlers().createFileHandlers(
                fileHandler: viewModel.fileHandler,
                maxfilesHandler: viewModel.maxfilesHandler,
                estimatedTimeHandler: viewModel.estimatedTimeHandler,
                memorypressurewarning: { _ in }
            )

            let extract = ExtractAndSaveJPGs()
            await extract.setFileHandlers(handlers)
            viewModel.currentExtractActor = extract // ← NEW: store it

            guard let url = viewModel.selectedSource?.url else { return }
            await extract.extractAndSaveAlljpgs(from: url)

            viewModel.currentExtractActor = nil // ← NEW: clean up
            viewModel.creatingthumbnails = false
        }
    }
}
