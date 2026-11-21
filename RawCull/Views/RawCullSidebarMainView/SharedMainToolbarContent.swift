//
//  SharedMainToolbarContent.swift
//  RawCull
//
//  Created by Thomas Evensen on 03/04/2026.
//

import SwiftUI

struct SharedMainToolbarContent: ToolbarContent {
    let catalog: CatalogWorkspace
    let selection: SelectionModel
    let ratings: RatingsModel
    let presentation: WorkspacePresentationModel
    let burstWorkflow: BurstWorkflowController
    let navigation: WorkspaceNavigationModel
    let catalogController: CatalogController
    let sharpnessModel: SharpnessScoringModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    let combinedReviewEnabled: Bool
    let isDisabled: Bool
    let toggleMetadataPanel: () -> Void

    var body: some ToolbarContent {
        if let summary = semanticSearchFeature.resultSummary,
           summary.resultCount > 0 {
            ToolbarItemGroup(placement: .status) {
                Button {
                    Task {
                        await semanticSearchFeature.adjustSelection(by: -1)
                    }
                } label: {
                    Label("Select Fewer Results", systemImage: "minus")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    isDisabled
                        || summary.resultCount <= 1
                        || semanticSelectionIsBusy,
                )
                .help("Remove the lowest-ranked image from the semantic-search selection")

                Text(
                    "\(summary.resultCount) of \(catalog.files.count) selected",
                    comment: "Semantic-search toolbar status: selected image count followed by total catalog image count.",
                )
                .font(.caption.monospacedDigit())
                .accessibilityLabel("Semantic search selection")
                .accessibilityValue(
                    "\(summary.resultCount) of \(catalog.files.count) catalog images",
                )

                Button {
                    Task {
                        await semanticSearchFeature.adjustSelection(by: 1)
                    }
                } label: {
                    Label("Select More Results", systemImage: "plus")
                }
                .labelStyle(.iconOnly)
                .disabled(
                    isDisabled
                        || summary.resultCount >= summary.rankedImageCount
                        || semanticSelectionIsBusy,
                )
                .help("Add the next highest-ranked image to the semantic-search selection")
            }
        }

        if !usesBurstWorkspaceChrome {
            Group {
                ToolbarItem(placement: .status) {
                    Button {
                        presentation.activeSheet = .scoringParams
                    } label: {
                        Label("Scoring Parameters", systemImage: "slider.horizontal.3")
                    }
                    .help("Configure sharpness scoring parameters")
                    .disabled(isDisabled)
                }

                ToolbarItem(placement: .status) {
                    Button {
                        presentation.activeSheet = .stats
                    } label: {
                        Label("Statistics", systemImage: "info.circle")
                    }
                    .help("Show scan statistics")
                    .disabled(isDisabled || catalog.files.isEmpty)
                }

                ToolbarItem(placement: .status) {
                    Button(action: selectReviewQueueMode) {
                        Label("Review", systemImage: "tray.full")
                    }
                    .help(reviewButtonHelp)
                    .disabled(isDisabled || reviewButtonIsDisabled)
                }

                ToolbarItem(placement: .status) {
                    Button(action: selectComparisonGridMode) {
                        Label("Compare", systemImage: "rectangle.split.2x1")
                    }
                    .help("Compare selected thumbnails")
                    .disabled(isDisabled ||
                        selection.selectedFileIDs.count <= 1 ||
                        catalog.selectedSource == nil ||
                        catalog.isCreatingThumbnails)
                }

                ToolbarItem(placement: .status) {
                    RatingFilterButtons(
                        activeRating: activeRatingInt,
                        onSelect: applyRatingFilter,
                        onClear: {
                            ratings.ratingFilter = .all
                            Task(priority: .background) { await catalogController.handleSortOrderChange() }
                        },
                    )
                    .padding(.trailing, 8)
                    .disabled(isDisabled || !hasExplicitRatings)
                }
            }

            // Trailing mode switcher — Loupe / Grid / Rated Grid.
            ToolbarItemGroup(placement: .status) {
                Button {
                    navigation.selectMainViewMode(.loupe)
                } label: {
                    Label("Loupe", systemImage: "rectangle.center.inset.filled")
                }
                .help("Loupe view")
                .disabled(isDisabled || navigation.mainViewMode == .loupe)

                Button {
                    selectSimilarityGridMode()
                } label: {
                    Label("Similarity", systemImage: "photo.stack")
                }
                .help("Similarity & burst grouping grid")
                .disabled(isDisabled ||
                    catalog.selectedSource == nil ||
                    catalog.filteredFiles.isEmpty ||
                    navigation.mainViewMode == .similarityGrid ||
                    catalog.isCreatingThumbnails)

                Button {
                    selectGridMode()
                } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                }
                .help("Thumbnail grid")
                .disabled(isDisabled ||
                    catalog.selectedSource == nil ||
                    catalog.filteredFiles.isEmpty ||
                    navigation.mainViewMode == .grid ||
                    catalog.isCreatingThumbnails)

                Button {
                    navigation.selectMainViewMode(.aiAnalysis)
                } label: {
                    Label("AI Analysis", systemImage: "rectangle.badge.sparkles")
                }
                .help("Analyze selected or tagged images with SAM 3 + CLIP or local Qwen")
                .disabled(isDisabled ||
                    catalog.selectedSource == nil ||
                    !hasAIAnalysisInput ||
                    navigation.mainViewMode == .aiAnalysis ||
                    catalog.isCreatingThumbnails)

                Button {
                    navigation.selectMainViewMode(.combinedReview)
                } label: {
                    Label("Combined Review", systemImage: "sparkles.rectangle.stack")
                }
                .help("Combined Review")
                .disabled(isDisabled ||
                    !combinedReviewEnabled ||
                    catalog.selectedSource == nil ||
                    !hasAIAnalysisInput ||
                    navigation.mainViewMode == .combinedReview ||
                    catalog.isCreatingThumbnails)

                Button {
                    navigation.selectMainViewMode(.ratedGrid)
                } label: {
                    Label("Rated", systemImage: "star.square.fill")
                }
                .help("Rated images grid")
                .disabled(isDisabled ||
                    catalog.selectedSource == nil ||
                    !showGridtaggedThumbnailWindow() ||
                    navigation.mainViewMode == .ratedGrid ||
                    catalog.isCreatingThumbnails)
            }
        }
    }

    private var usesBurstWorkspaceChrome: Bool {
        burstWorkflow.activeBurstComparisonGroupID != nil
    }

    private var semanticSelectionIsBusy: Bool {
        burstWorkflow.burstAnalysisProgress.isRunning
            || sharpnessModel.isScoring
            || similarityFeature.isBusy
    }

    private var semanticSelectionCount: Int? {
        semanticSearchFeature.resultSummary?.resultCount
    }

    private var reviewButtonHelp: LocalizedStringResource {
        if semanticSelectionCount != nil {
            "Review the semantic-search selection using the existing burst index"
        } else {
            "Show burst groups that need review"
        }
    }

    private var reviewButtonIsDisabled: Bool {
        guard catalog.selectedSource != nil,
              !catalog.isCreatingThumbnails,
              !semanticSelectionIsBusy
        else { return true }

        if let semanticSelectionCount {
            return semanticSelectionCount < 2
        }
        return burstWorkflow.burstReviewSummary.needsReview == 0
    }

    private var activeRatingInt: Int? {
        switch ratings.ratingFilter {
        case .all: nil
        case .rejected: -1
        case .keepers: 0
        case let .stars(n): n
        }
    }

    private func selectGridMode() {
        ratings.ratingFilter = .all
        Task(priority: .background) { await catalogController.handleSortOrderChange() }
        navigation.selectMainViewMode(.grid)
    }

    private func selectSimilarityGridMode() {
        ratings.ratingFilter = .all
        burstWorkflow.burstReviewQueueFilter = .all
        Task(priority: .background) { await catalogController.handleSortOrderChange() }
        navigation.selectMainViewMode(.similarityGrid)
    }

    private func selectReviewQueueMode() {
        ratings.ratingFilter = .all
        navigation.selectMainViewMode(.similarityGrid)
        if semanticSelectionCount != nil {
            Task { @MainActor in
                await catalogController.handleSortOrderChange()
                guard !Task.isCancelled else { return }

                if burstWorkflow.canUseExistingBurstGroupIndexForActiveScope {
                    burstWorkflow.useExistingBurstGroupIndex()
                    return
                }

                if await burstWorkflow.restoreExistingFullCatalogBurstAnalysis() {
                    guard !Task.isCancelled else { return }
                    burstWorkflow.useExistingBurstGroupIndex()
                    return
                }

                burstWorkflow.burstFullReindexRequest = .semanticReview
            }
        } else {
            burstWorkflow.burstReviewQueueFilter = .needsReview
            similarityFeature.burstModeActive = true
            Task(priority: .background) {
                await catalogController.handleSortOrderChange()
            }
        }
    }

    private func selectComparisonGridMode() {
        let selectedIDs = selection.selectedFileIDs
        let orderedIDs = catalog.filteredFiles
            .filter { selectedIDs.contains($0.id) }
            .map(\.id)
        selection.comparisonFileIDs = Array(orderedIDs.prefix(4))
        navigation.selectMainViewMode(.comparisonGrid)
    }

    private func showGridtaggedThumbnailWindow() -> Bool {
        guard let catalogURL = catalog.selectedSource?.url,
              let index = ratings.cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalogURL })
        else {
            return false
        }
        if let records = ratings.cullingModel.savedFiles[index].filerecords {
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
        ratings.ratingFilter = ratings.ratingFilter == newFilter ? .all : newFilter
        Task(priority: .background) { await catalogController.handleSortOrderChange() }
    }

    private var hasExplicitRatings: Bool {
        guard let catalog = catalog.selectedSource?.url else { return false }
        return ratings.cullingModel.hasExplicitRatings(in: catalog)
    }

    private var hasAIAnalysisInput: Bool {
        !catalogController.aiAnalysisFiles(for: .gridSelection).isEmpty
            || !catalogController.aiAnalysisFiles(for: .taggedImages).isEmpty
    }
}
