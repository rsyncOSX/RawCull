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
            Button(action: openCopyView) {
                Label("Copy", systemImage: "document.on.document")
            }
            .disabled(viewModel.creatingthumbnails || viewModel.selectedSource == nil)
            .help("Copy tagged images to destination...")
        }

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
                Label("Saved Files", systemImage: "square.and.arrow.down")
            }
            .help("Show saved files")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleShowInspector) {
                Label("Inspector", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .help("Show inspector")
        }

        ToolbarItem(placement: .status) {
            Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                Label("Sharpness", systemImage: "arrow.up.arrow.down")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || viewModel.sharpnessModel.scores.isEmpty)
            .labelStyle(.iconOnly)
            .help("Sort thumbnails sharpest-first")
            .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, _ in
                Task(priority: .background) {
                    await viewModel.handleSortOrderChange()
                }
            }
        }

        ToolbarItem(placement: .status) {
            HStack(spacing: 4) {
                ForEach([(-1, Color.red), (2, Color.yellow), (3, Color.green), (4, Color.blue), (5, Color.purple)], id: \.0) { rating, color in
                    Button { applyRatingFilter(rating) } label: {
                        Circle()
                            .fill(color.opacity(isRatingFilterActive(rating) ? 1.0 : 0.25))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help(rating == -1 ? "Show only rejected images" : "Show only \(rating)-star images")
                }

                // Keepers button (rating == 0)
                Button { applyRatingFilter(0) } label: {
                    Text("P")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(viewModel.ratingFilter == .keepers ? .white : .secondary)
                        .frame(width: 18, height: 18)
                        .background(
                            Circle()
                                .fill(viewModel.ratingFilter == .keepers ? Color.accentColor : Color.secondary.opacity(0.2))
                        )
                }
                .buttonStyle(.borderless)
                .contentShape(Rectangle())
                .help("Show only keepers (rating 0)")

                if viewModel.ratingFilter != .all {
                    Button {
                        viewModel.ratingFilter = .all
                        Task(priority: .background) { await viewModel.handleSortOrderChange() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .contentShape(Rectangle())
                    .help("Show all thumbnails")
                }
            }
            .disabled(viewModel.selectedSource == nil)
        }

    }

    func applyRatingFilter(_ rating: Int) {
        let newFilter: RatingFilter = switch rating {
        case -1: .rejected
        case 0: .keepers
        default: .minimum(rating)
        }
        viewModel.ratingFilter = viewModel.ratingFilter == newFilter ? .all : newFilter
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
    }

    func isRatingFilterActive(_ rating: Int) -> Bool {
        switch rating {
        case -1: viewModel.ratingFilter == .rejected
        case 0: viewModel.ratingFilter == .keepers
        default: viewModel.ratingFilter == .minimum(rating)
        }
    }

    func openCopyView() {
        viewModel.sheetType = .copytasksview
        viewModel.showcopyARWFilesView = true
    }

    func toggleShowInspector() {
        viewModel.hideInspector.toggle()
    }

    func toggleshowsavedfiles() {
        viewModel.showSavedFiles.toggle()
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
