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
                    Text("Reset \(viewModel.scale * 100, format: .number.precision(.fractionLength(0)))%")
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

        ToolbarItem(placement: .status) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowdetailonly) {
                Label("Details", systemImage: "photo.stack")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Show details")
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

    func toggleshowdetailonly() {
        showDetailOnly.toggle()
    }

    func openGridThumbnailWindow() {
        gridthumbnailviewmodel.open(
            cullingModel: viewModel.cullingModel,
            selectedSource: viewModel.selectedSource,
            filteredFiles: viewModel.filteredFiles,
        )
        openWindow(id: WindowIdentifier.gridThumbnails.rawValue)
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
