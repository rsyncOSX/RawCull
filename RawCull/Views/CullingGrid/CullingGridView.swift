//
//  CullingGridView.swift
//  RawCull
//
//  Shared culling grid extracted from `GridThumbnailSelectionView` and
//  `SimilarityGridSelectionView`. Owns the LazyVGrid, burst-mode render
//  cache, selection handling, rating filter, scroll-to-selection, the
//  three progress overlays, and the "N selected" toolbar status. The
//  caller supplies the header content via a `@ViewBuilder` slot and
//  may layer additional toolbar items on top with its own `.toolbar`.
//

import AppKit
import RawCullCore
import SwiftUI

// MARK: - Rating filter

// MARK: - Burst-group section header

// Renders a single burst-group section header with the review workflow actions.

// MARK: - CullingGridView

struct CullingGridView<Header: View>: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(BurstWorkflowController.self) private var burstWorkflow
    @Environment(WorkspaceNavigationModel.self) private var navigation
    @Environment(CatalogController.self) private var catalogController
    @Environment(CullingController.self) private var culling
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    @ViewBuilder let header: () -> Header
    var batchBadgeSelectionEnabled: () -> Bool = { false }

    @State private var ratingFilter: GridRatingFilter = .all
    @State private var batchRating: Int = 3

    private var projection: CullingGridProjection {
        catalogController.cullingGridProjection(ratingFilter: ratingFilter)
    }

    private var visibleBurstGroups: [CullingGridVisibleBurstGroup] {
        projection.groups
    }

    private var hasSharpnessScoresSnapshot: Bool {
        projection.key.hasSharpnessScores
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                header()
                if batchBadgeSelectionEnabled(), !badgeSelectionItems.isEmpty {
                    BatchBadgeSelectionControlsView(
                        items: badgeSelectionItems,
                        selectedCount: selection.selectedFileIDs.count,
                        rating: $batchRating,
                        onSelectBadge: selectFiles(matchingBadge:),
                        onApplyRating: applyBatchRating,
                    )
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            if navigation.showsBurstGroups {
                CullingQueueHeader(
                    title: reviewQueueTitle, isSingleImages: burstWorkflow.burstReviewQueueFilter == .singleImages,
                    burstCount: visibleBurstGroups.count,
                    onBack: { similarityFeature.burstModeActive = false },
                )
            }

            ZStack {
                // Grid view
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if navigation.showsBurstGroups {
                                LazyVStack(spacing: 16) {
                                    ForEach(renderedBurstGroups) { group in
                                        CullingBurstGroupCard(
                                            group: group, number: burstNumber(for: group.id),
                                            select: handleToggleSelection(for:),
                                            markBurstGroupReviewed: markBurstGroupReviewed,
                                            deferBurstGroup: deferBurstGroup,
                                        )
                                    }
                                }
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: CGFloat(200)), spacing: 12)],
                                    spacing: 12,
                                ) {
                                    // ── Flat mode (default) ───────────────────────────
                                    ForEach(files, id: \.id) { file in
                                        CullingGridThumbnail(file: file,
                                            semanticResultRank: semanticResultRank(for: file),
                                            semanticResultCount: semanticResultCount,
                                            semanticResultScore: semanticResultScore(for: file),
                                            onSelect: { handleToggleSelection(for: file) },
                                            onDoubleSelect: { handleDoubleSelect(for: file) },
                                        )
                                        .id(file.id)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                    .onAppear {
                        guard let id = selection.selectedFileID else { return }
                        // Defer one runloop cycle so LazyVGrid has laid out before scrolling
                        Task { @MainActor in
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .onChange(of: selection.selectedFileID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                    .onChange(of: sortScrollState) { _, newState in
                        guard
                            let selectedID = CullingGridSelectionCoordinator.scrollTargetAfterSortChange(
                                state: newState,
                                selectedFileID: selection.selectedFileID,
                                showsBurstGroups: navigation.showsBurstGroups,
                            )
                        else { return }

                        // Let LazyVGrid apply the new ordering before locating the selected cell.
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                }

                CullingGridProgressOverlay(similarityFeature: similarityFeature,
                )
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.15), value: navigation.showsBurstGroups)
        .animation(.easeInOut(duration: 0.15), value: ratingFilter)
        .task(id: catalog.selectedSource) {
            await ThumbnailLoader.shared.cancelAll()
        }
        .onChange(of: gridCacheKey, initial: true) { _, _ in
            recomputeGridCache()
        }
        .thumbnailKeyNavigation(
            axis: .grid,
            files: { visibleSelectionFiles },
            onBurstKeyPress: handleBurstKeyPress,
        )
    }

    // MARK: - Selection handlers

    private func handleToggleSelection(for file: FileItem) {
        let next = CullingGridSelectionCoordinator.toggleSelection(
            fileID: file.id,
            state: selectionState,
            visibleIDs: visibleSelectionIDs,
            modifier: CullingGridSelectionModifier(flags: NSEvent.modifierFlags),
        )
        applySelectionState(next)
    }

    private func handleDoubleSelect(for file: FileItem) {
        selection.selectedFileID = file.id
        navigation.openZoomOverlay(navigationIDs: zoomNavigationIDs(for: file))
    }

    private func selectFiles(matchingBadge badge: String) {
        let matchingIDs = CullingGridSelectionCoordinator.matchingIDs(
            forBadge: badge,
            visibleFiles: visibleSelectionFiles,
            burstGroupLookup: similarityFeature.burstGroupLookup,
            burstAnalysisResults: burstWorkflow.burstAnalysisResults,
            saliencyInfo: sharpnessModel.saliencyInfo,
        )
        let next = CullingGridSelectionCoordinator.selectFiles(
            matchingIDs: matchingIDs,
            state: selectionState,
            visibleFiles: visibleSelectionFiles,
            modifier: CullingGridSelectionModifier(flags: NSEvent.modifierFlags),
        )
        applySelectionState(next)
    }

    private func applyBatchRating() {
        let selectedIDs = selection.selectedFileIDs
        guard !selectedIDs.isEmpty else { return }
        let selectedFiles = CullingGridSelectionCoordinator.actionFiles(
            requestedIDs: selectedIDs,
            renderedFiles: visibleSelectionFiles,
        )
        guard !selectedFiles.isEmpty else { return }
        culling.updateRating(for: selectedFiles, rating: batchRating)
    }

    private var visibleSelectionFiles: [FileItem] {
        projection.selectionFiles
    }

    private var visibleSelectionIDs: [FileItem.ID] {
        projection.selectionIDs
    }

    private var renderedBurstGroups: [CullingGridVisibleBurstGroup] {
        projection.groups
    }

    private func zoomNavigationIDs(for file: FileItem) -> [FileItem.ID] {
        CullingGridSelectionCoordinator.zoomNavigationIDs(
            for: file,
            showsBurstGroups: navigation.showsBurstGroups,
            visibleBurstGroups: renderedBurstGroups,
            files: files,
        )
    }

    private var badgeSelectionItems: [BatchBadgeSelectionItem] {
        projection.badges
    }

    private var selectionState: CullingGridSelectionState {
        CullingGridSelectionState(
            selectedFileID: selection.selectedFileID,
            selectedFileIDs: selection.selectedFileIDs,
        )
    }

    private func applySelectionState(_ state: CullingGridSelectionState) {
        selection.selectedFileID = state.selectedFileID
        selection.selectedFileIDs = state.selectedFileIDs
    }

    private func synchronizeSelectionWithRenderedFiles() {
        let renderedIDs = visibleSelectionIDs
        selection.cullingGridRenderedFileIDs = renderedIDs
        applySelectionState(
            CullingGridSelectionCoordinator.reconcileSelection(
                selectionState,
                visibleIDs: renderedIDs,
            ),
        )
    }

    // MARK: - Burst grouping helpers

    private var gridCacheKey: CullingGridProjectionKey {
        projection.key
    }

    private func recomputeGridCache() {
        synchronizeSelectionWithRenderedFiles()
    }

    private var reviewQueueTitle: String {
        switch burstWorkflow.burstReviewQueueFilter {
        case .all: "All bursts"
        case .singleImages: "Single Images"
        case .needsReview: "Needs Review"
        case .deferred: "Deferred"
        case .markedReviewed: "Marked Reviewed"
        case .reviewed: "Completed"
        }
    }

    private func burstNumber(for groupID: Int) -> Int {
        projection.groupNumbers[groupID] ?? groupID + 1
    }

    private func markBurstGroupReviewed(_ groupID: Int) {
        burstWorkflow.toggleBurstGroupReviewed(groupID: groupID)
    }

    private func deferBurstGroup(_ groupID: Int) {
        burstWorkflow.toggleBurstGroupDeferred(groupID: groupID)
    }

    private func handleBurstKeyPress(_ characters: String) -> KeyPress.Result {
        guard navigation.showsBurstGroups else { return .ignored }
        if characters == "\u{1b}" {
            similarityFeature.burstModeActive = false
            return .handled
        }
        if characters == "u" || characters == "U" {
            burstWorkflow.undoLastBurstAction()
            return .handled
        }
        guard let groupFiles = currentBurstGroupFiles
        else { return .ignored }

        switch characters {
        case "\r":
            burstWorkflow.compareBurstGroup(groupFiles)
            return .handled

        case "B", "b":
            guard canApplyOneClickCulling(to: groupFiles) else { return .ignored }
            burstWorkflow.keepBestInGroup(from: groupFiles)
            return .handled

        case "2":
            guard canApplyOneClickCulling(to: groupFiles) else { return .ignored }
            burstWorkflow.keepTopTwoInGroup(from: groupFiles)
            return .handled

        default:
            return .ignored
        }
    }

    private var currentBurstGroupFiles: [FileItem]? {
        if burstWorkflow.burstReviewQueueFilter == .singleImages {
            return renderedBurstGroups.first?.files
        }
        guard let selectedID = selection.selectedFileID,
              let groupID = similarityFeature.burstGroupLookup[selectedID]
        else { return nil }
        return renderedBurstGroups.first { $0.id == groupID }?.files
    }

    private func canApplyOneClickCulling(to groupFiles: [FileItem]) -> Bool {
        guard let groupID = groupFiles.lazy.compactMap({ similarityFeature.burstGroupLookup[$0.id] }).first,
              let result = burstWorkflow.burstAnalysisResult(for: groupID)
        else { return false }
        return result.canApplyOneClickCulling(hasSharpnessScores: hasSharpnessScoresSnapshot)
    }

    // MARK: - Rating filter

    var files: [FileItem] {
        projection.files
    }

    private var sortScrollState: CullingGridSortScrollState {
        CullingGridSortScrollState(
            isSharpnessSortingActive: sharpnessModel.sortBySharpness,
            isSimilaritySortingActive: similarityFeature.isSimilaritySortingActive,
            orderedFileIDs: projection.fileIDs,
        )
    }

    private var semanticResultCount: Int? {
        guard !navigation.showsBurstGroups,
              let summary = semanticSearchFeature.resultSummary,
              summary.resultCount > 0
        else { return nil }
        return summary.resultCount
    }

    private func semanticResultRank(for file: FileItem) -> Int? {
        guard semanticResultCount != nil else { return nil }
        return semanticSearchFeature.resultEvidence(for: file.id)?.rank
    }

    private func semanticResultScore(for file: FileItem) -> Float? {
        guard semanticResultCount != nil else { return nil }
        return semanticSearchFeature.resultEvidence(for: file.id)?.score
    }
}
