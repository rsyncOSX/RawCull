//
//  SharedMainToolbarContent.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

struct SharedMainToolbarContent: ToolbarContent {
    @Bindable var viewModel: RawCullViewModel
    var columnVisibility: Binding<NavigationSplitViewVisibility>
    let toggleInspector: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                if columnVisibility.wrappedValue == .all {
                    columnVisibility.wrappedValue = viewModel.mainViewMode == .loupe ? .doubleColumn : .detailOnly
                } else {
                    columnVisibility.wrappedValue = .all
                }
            } label: {
                Label("Toggle Sidebar", systemImage: "sidebar.leading")
            }
            .help("Show/hide sidebar")
        }

        ToolbarItem(placement: .status) {
            Button(action: openCopyView) {
                Label("Copy", systemImage: "document.on.document")
            }
            .disabled(viewModel.creatingthumbnails || viewModel.selectedSource == nil)
            .help("Copy tagged images to destination...")
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

        // Trailing mode switcher — Loupe / Grid / Rated Grid.
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                viewModel.mainViewMode = .loupe
            } label: {
                Label("Loupe", systemImage: "rectangle.center.inset.filled")
            }
            .help("Loupe view")
            .disabled(viewModel.mainViewMode == .loupe)

            Button {
                selectGridMode()
            } label: {
                Label("Grid", systemImage: "square.grid.2x2")
            }
            .help("Thumbnail grid")
            .disabled(viewModel.selectedSource == nil || viewModel.filteredFiles.isEmpty || viewModel.mainViewMode == .grid)

            Button {
                viewModel.mainViewMode = .ratedGrid
            } label: {
                Label("Rated", systemImage: "star.square.fill")
            }
            .help("Rated images grid")
            .disabled(viewModel.selectedSource == nil || !showGridtaggedThumbnailWindow() || viewModel.mainViewMode == .ratedGrid)
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

    private func selectGridMode() {
        viewModel.ratingFilter = .all
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
        viewModel.mainViewMode = .grid
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
