//
//  SharedMainToolbarContent.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

struct SharedMainToolbarContent: ToolbarContent {
    @Bindable var viewModel: RawCullViewModel
    let toggleMetadataPanel: () -> Void

    var body: some ToolbarContent {
        if case let .results(summary) = viewModel.similarityModel.semanticSearchState,
           summary.resultCount > 0 {
            ToolbarItemGroup(placement: .status) {
                Button {
                    Task {
                        await viewModel.adjustSemanticSearchSelection(by: -1)
                    }
                } label: {
                    Label("Select Fewer Results", systemImage: "minus")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    summary.resultCount <= 1
                        || semanticSelectionIsBusy,
                )
                .help("Remove the lowest-ranked image from the semantic-search selection")

                Text(
                    "\(summary.resultCount) of \(viewModel.files.count) selected",
                    comment: "Semantic-search toolbar status: selected image count followed by total catalog image count.",
                )
                .font(.caption.monospacedDigit())
                .accessibilityLabel("Semantic search selection")
                .accessibilityValue(
                    "\(summary.resultCount) of \(viewModel.files.count) catalog images",
                )

                Button {
                    Task {
                        await viewModel.adjustSemanticSearchSelection(by: 1)
                    }
                } label: {
                    Label("Select More Results", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    summary.resultCount >= summary.rankedImageCount
                        || semanticSelectionIsBusy,
                )
                .help("Add the next highest-ranked image to the semantic-search selection")
            }
        }

        if !usesBurstWorkspaceChrome {
            Group {
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
                    Button(action: selectReviewQueueMode) {
                        Label("Review", systemImage: "tray.full")
                    }
                    .help(reviewButtonHelp)
                    .disabled(reviewButtonIsDisabled)
                }

                ToolbarItem(placement: .status) {
                    Button(action: selectComparisonGridMode) {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                    }
                    .help("Compare selected thumbnails")
                    .disabled(viewModel.selectedFileIDs.count <= 1 ||
                        viewModel.selectedSource == nil ||
                        viewModel.creatingthumbnails)
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
                    .disabled(!hasExplicitRatings)
                }
            }

            // Trailing mode switcher — Loupe / Grid / Rated Grid.
            ToolbarItemGroup(placement: .status) {
                Button {
                    viewModel.selectMainViewMode(.loupe)
                } label: {
                    Label("Loupe", systemImage: "rectangle.center.inset.filled")
                }
                .help("Loupe view")
                .disabled(viewModel.mainViewMode == .loupe)

                Button {
                    selectSimilarityGridMode()
                } label: {
                    Label("Similarity", systemImage: "photo.stack")
                }
                .help("Similarity & burst grouping grid")
                .disabled(viewModel.selectedSource == nil ||
                    viewModel.filteredFiles.isEmpty ||
                    viewModel.mainViewMode == .similarityGrid ||
                    viewModel.creatingthumbnails)

                Button {
                    selectGridMode()
                } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                }
                .help("Thumbnail grid")
                .disabled(viewModel.selectedSource == nil ||
                    viewModel.filteredFiles.isEmpty ||
                    viewModel.mainViewMode == .grid ||
                    viewModel.creatingthumbnails)

                Button {
                    viewModel.selectMainViewMode(.ratedGrid)
                } label: {
                    Label("Rated", systemImage: "star.square.fill")
                }
                .help("Rated images grid")
                .disabled(viewModel.selectedSource == nil ||
                    !showGridtaggedThumbnailWindow() ||
                    viewModel.mainViewMode == .ratedGrid ||
                    viewModel.creatingthumbnails)
            }
        }
    }

    private var usesBurstWorkspaceChrome: Bool {
        viewModel.activeBurstComparisonGroupID != nil
    }

    private var semanticSelectionIsBusy: Bool {
        viewModel.burstAnalysisProgress.isRunning
            || viewModel.sharpnessModel.isScoring
            || viewModel.similarityModel.isIndexing
            || viewModel.similarityModel.isGrouping
    }

    private var semanticSelectionCount: Int? {
        guard case let .results(summary) =
            viewModel.similarityModel.semanticSearchState
        else { return nil }
        return summary.resultCount
    }

    private var reviewButtonHelp: LocalizedStringResource {
        if semanticSelectionCount != nil {
            "Review the semantic-search selection using the existing burst index"
        } else {
            "Show burst groups that need review"
        }
    }

    private var reviewButtonIsDisabled: Bool {
        guard viewModel.selectedSource != nil,
              !viewModel.creatingthumbnails,
              !semanticSelectionIsBusy
        else { return true }

        if let semanticSelectionCount {
            return semanticSelectionCount < 2
        }
        return viewModel.burstReviewSummary.needsReview == 0
    }

    private var activeRatingInt: Int? {
        switch viewModel.ratingFilter {
        case .all: nil
        case .rejected: -1
        case .keepers: 0
        case let .stars(n): n
        }
    }

    private func selectGridMode() {
        viewModel.ratingFilter = .all
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
        viewModel.selectMainViewMode(.grid)
    }

    private func selectSimilarityGridMode() {
        viewModel.ratingFilter = .all
        viewModel.burstReviewQueueFilter = .all
        Task(priority: .background) { await viewModel.handleSortOrderChange() }
        viewModel.selectMainViewMode(.similarityGrid)
    }

    private func selectReviewQueueMode() {
        viewModel.ratingFilter = .all
        viewModel.selectMainViewMode(.similarityGrid)
        if semanticSelectionCount != nil {
            Task { @MainActor in
                await viewModel.handleSortOrderChange()
                guard !Task.isCancelled else { return }

                if viewModel.canUseExistingBurstGroupIndexForActiveScope {
                    viewModel.useExistingBurstGroupIndex()
                    return
                }

                if await viewModel.restoreExistingFullCatalogBurstAnalysis() {
                    guard !Task.isCancelled else { return }
                    viewModel.useExistingBurstGroupIndex()
                    return
                }

                viewModel.burstFullReindexRequest = .semanticReview
            }
        } else {
            viewModel.burstReviewQueueFilter = .needsReview
            viewModel.similarityModel.burstModeActive = true
            Task(priority: .background) {
                await viewModel.handleSortOrderChange()
            }
        }
    }

    private func selectComparisonGridMode() {
        let selectedIDs = viewModel.selectedFileIDs
        let orderedIDs = viewModel.filteredFiles
            .filter { selectedIDs.contains($0.id) }
            .map(\.id)
        viewModel.comparisonFileIDs = Array(orderedIDs.prefix(4))
        viewModel.selectMainViewMode(.comparisonGrid)
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

    private var hasExplicitRatings: Bool {
        guard let catalog = viewModel.selectedSource?.url else { return false }
        return viewModel.cullingModel.hasExplicitRatings(in: catalog)
    }
}
