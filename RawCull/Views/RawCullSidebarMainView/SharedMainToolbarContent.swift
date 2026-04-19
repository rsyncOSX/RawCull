//
//  SharedMainToolbarContent.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

struct SharedMainToolbarContent: ToolbarContent {
    @Bindable var viewModel: RawCullViewModel
    let toggleInspector: () -> Void

    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    var body: some ToolbarContent {
        Group {
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
                Toggle(isOn: Binding(
                    get: { settings.showScoringBadge },
                    set: { settings.showScoringBadge = $0; Task { await settings.saveSettings() } },
                )) {
                    Label("Score Badge", systemImage: "number.circle")
                }
                .toggleStyle(.button)
                .help("Show sharpness score badge on thumbnails (disable for smoother scrolling)")
            }

            ToolbarItem(placement: .status) {
                Toggle(isOn: Binding(
                    get: { settings.showSaliencyBadge },
                    set: { settings.showSaliencyBadge = $0; Task { await settings.saveSettings() } },
                )) {
                    Label("Saliency Badge", systemImage: "eye.circle")
                }
                .toggleStyle(.button)
                .help("Show saliency badge on thumbnails")
            }

            ToolbarItem(placement: .status) {
                Button {
                    viewModel.activeSheet = .scoringParams
                } label: {
                    Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                }
                .help("Configure sharpness scoring parameters")
            }

            ToolbarItem(placement: .status) {
                Button {
                    viewModel.activeSheet = .stats
                } label: {
                    Label("Statistics", systemImage: "info.circle")
                }
                .help("Show scan statistics")
                .disabled(viewModel.files.isEmpty)
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

        // Trailing mode switcher — Loupe / Grid / Rated Grid.
        ToolbarItemGroup(placement: .status) {
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
