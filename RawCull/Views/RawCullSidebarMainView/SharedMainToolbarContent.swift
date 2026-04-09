//
//  SharedMainToolbarContent.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

struct SharedMainToolbarContent: ToolbarContent {
    @Bindable var viewModel: RawCullViewModel
    /// `true` when hosted in `HorizontalMainThumbnailsListView` (shows the "back to vertical" button),
    /// `false` when hosted in `RawCullMainView` (shows the "go to horizontal" button).
    let isHorizontal: Bool
    let toggleLayout: () -> Void
    let toggleInspector: () -> Void
    let openGridThumbnail: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Button(action: openCopyView) {
                Label("Copy", systemImage: "document.on.document")
            }
            .disabled(viewModel.creatingthumbnails || viewModel.selectedSource == nil)
            .help("Copy tagged images to destination...")
        }

        ToolbarItem(placement: .status) {
            Button(action: openGridThumbnail) {
                Label("Grid View", systemImage: "square.grid.2x2")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
            .help("Open thumbnail grid view")
        }

        ToolbarItem(placement: .status) {
            Button(action: opentaggedGridThumbnailWindow) {
                Label("Grid Tagged Images", systemImage: "square.grid.2x2.fill")
            }
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || !showGridtaggedThumbnailWindow())
            .help("Open tagged thumbnail grid view")
        }

        if isHorizontal {
            ToolbarItem(placement: .status) {
                Button(action: toggleLayout) {
                    Label("Horizontal", systemImage: "arrow.up.and.down.text.horizontal")
                }
                .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
                .help("Show Vertical thumbnails")
                .labelStyle(.iconOnly)
            }
        } else {
            ToolbarItem(placement: .status) {
                Button(action: toggleLayout) {
                    Label("Vertical", systemImage: "arrow.left.and.right.text.vertical")
                }
                .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty)
                .help("Show Horizontal thumbnails")
            }
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleshowsavedfiles) {
                Label("Saved Files", systemImage: "square.and.arrow.down")
            }
            .help("Show saved files")
        }

        ToolbarItem(placement: .status) {
            Button(action: toggleInspector) {
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
            RatingFilterButtons(
                activeRating: activeRatingInt,
                onSelect: applyRatingFilter,
                onClear: {
                    viewModel.ratingFilter = .all
                    Task(priority: .background) { await viewModel.handleSortOrderChange() }
                },
            )
            .padding(.trailing, 8)
            .disabled(viewModel.selectedSource == nil)
        }
    }

    private var activeRatingInt: Int? {
        switch viewModel.ratingFilter {
        case .all: nil
        case .rejected: -1
        case .keepers: 0
        case let .stars(n): n
        }
    }

    private func openCopyView() {
        viewModel.sheetType = .copytasksview
        viewModel.showcopyARWFilesView = true
    }

    private func toggleshowsavedfiles() {
        viewModel.showSavedFiles.toggle()
    }

    private func opentaggedGridThumbnailWindow() {
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

    private func applyRatingFilter(_ rating: Int) {
        let newFilter: RatingFilter = switch rating {
        case -1: .rejected
        case 0: .keepers
        default: .stars(rating)
        }
        viewModel.ratingFilter = viewModel.ratingFilter == newFilter ? .all : newFilter
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
    }
}
