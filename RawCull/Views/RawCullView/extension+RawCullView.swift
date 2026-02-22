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
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 16))
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
                    Text("Reset")
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
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 16))
                })
                .disabled(viewModel.scale >= 4.0)
                .help("Zoom in")
            }

            ToolbarItem(placement: .secondaryAction) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Zoom: \(String(format: "%.0f%%", viewModel.scale * 100))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: openGridThumbnailWindow) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem { Spacer() }
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

    // File table

    var filetableview: some View {
        VStack(alignment: .leading) {
            Table(viewModel.filteredFiles.compactMap { file in
                (viewModel.getRating(for: file) >= viewModel.rating) ? file : nil
            },
            selection: $viewModel.selectedFileID,
            sortOrder: $viewModel.sortOrder) {
                TableColumn("", value: \.id) { file in
                    Button(action: {
                        handleToggleSelection(for: file)
                    }, label: {
                        Image(systemName: marktoggle(for: file) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.blue)
                    })
                    .buttonStyle(.plain)
                }
                .width(30)
                TableColumn("Rating") { file in
                    RatingView(
                        rating: viewModel.getRating(for: file),
                        onChange: { newRating in
                            // If not toggled, toggle it on first
                            if !marktoggle(for: file) {
                                handleToggleSelection(for: file)
                            }
                            viewModel.updateRating(for: file, rating: newRating)
                        }
                    )
                }
                .width(90)
                TableColumn("Name", value: \.name) { file in
                    HStack(spacing: 8) {
                        // Visual indicator for previously selected file
                        if file.id == viewModel.previouslySelectedFileID {
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(.blue)
                                    .frame(width: 3)
                                Spacer()
                            }
                        }
                        Text(file.name)
                    }
                }
                TableColumn("Size", value: \.size) { file in
                    Text(file.formattedSize).monospacedDigit()
                }
                .width(75)
                TableColumn("Modified", value: \.dateModified) { file in
                    Text(file.dateModified, style: .date)
                }
            }

            if showPhotoGridView() {
                Divider()

                PhotoGridView(
                    cullingmanager: viewModel.cullingModel,
                    files: viewModel.filteredFiles,
                    photoURL: viewModel.selectedSource?.url,
                    onPhotoSelected: { file in
                        viewModel.selectedFileID = file.id
                        viewModel.selectedFile = file
                        viewModel.isInspectorPresented = true
                    }
                )
            }
        }
        .onChange(of: viewModel.selectedFileID) {
            // Track the previously selected file
            if viewModel.selectedFileID != nil {
                viewModel.previouslySelectedFileID = viewModel.selectedFileID
            }

            if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                viewModel.selectedFileID = viewModel.files[index].id
                viewModel.selectedFile = viewModel.files[index]
                viewModel.isInspectorPresented = true

                // Only update zoom window content if it's already in focus (don't open it)
                let file = viewModel.files[index]
                if zoomCGImageWindowFocused || zoomNSImageWindowFocused {
                    JPGPreviewHandler.handle(
                        file: file,
                        useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                        setNSImage: { nsImage = $0 },
                        setCGImage: { cgImage = $0 },
                        openWindow: { _ in } // Don't open window on row selection
                    )
                }
            } else {
                viewModel.isInspectorPresented = false
            }
        }
        .onChange(of: viewModel.focusPressEnter) {
            if viewModel.focusPressEnter {
                if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                    viewModel.selectedFileID = viewModel.files[index].id
                    viewModel.selectedFile = viewModel.files[index]
                    viewModel.isInspectorPresented = true

                    // Only update zoom window content if it's already in focus (don't open it)
                    let file = viewModel.files[index]
                    if zoomCGImageWindowFocused || zoomNSImageWindowFocused {
                        JPGPreviewHandler.handle(
                            file: file,
                            useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                            setNSImage: { nsImage = $0 },
                            setCGImage: { cgImage = $0 },
                            openWindow: { _ in } // Don't open window on row selection
                        )
                    }
                } else {
                    viewModel.isInspectorPresented = false
                }
            }
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { _ in
        } primaryAction: { _ in
            guard let selectedID = viewModel.selectedFileID,
                  let file = viewModel.files.first(where: { $0.id == selectedID }) else { return }

            JPGPreviewHandler.handle(
                file: file,
                useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                setNSImage: { nsImage = $0 },
                setCGImage: { cgImage = $0 },
                openWindow: { id in openWindow(id: id) }
            )
        }
        .onKeyPress(.space) {
            guard let selectedID = viewModel.selectedFileID,
                  let file = viewModel.files.first(where: { $0.id == selectedID }) else { return .handled }

            JPGPreviewHandler.handle(
                file: file,
                useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
                setNSImage: { nsImage = $0 },
                setCGImage: { cgImage = $0 },
                openWindow: { id in openWindow(id: id) }
            )
            return .handled
        }
    }

    // MARK: - Helper Functions

    func marktoggle(for file: FileItem) -> Bool {
        if let index = viewModel.cullingModel.savedFiles.firstIndex(where: { $0.catalog == viewModel.selectedSource?.url }),
           let filerecords = viewModel.cullingModel.savedFiles[index].filerecords {
            return filerecords.contains { $0.fileName == file.name }
        }
        return false
    }

    func showPhotoGridView() -> Bool {
        guard let catalogURL = viewModel.selectedSource?.url,
              let index = viewModel.cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalogURL })
        else {
            return false
        }
        // Show the grid when there are filerecords and the collection is not empty
        if let records = viewModel.cullingModel.savedFiles[index].filerecords {
            return !records.isEmpty
        }
        return false
    }

    func handleToggleSelection(for file: FileItem) {
        viewModel.cullingModel.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name
        )
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
            guard let url = viewModel.selectedSource?.url else { return }
            await extract.extractAndSaveAlljpgs(from: url)

            viewModel.creatingthumbnails = false
        }
    }
}
