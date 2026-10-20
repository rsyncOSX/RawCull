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

enum GridRatingFilter: Hashable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}

// MARK: - Burst-group section header

/// Renders a single burst-group section header with the review workflow actions.
private struct BurstGroupHeaderView: View {
    let groupNumber: Int
    let files: [FileItem]
    let analysis: BurstAnalysisResult?
    let onReviewed: (Int) -> Void
    let onDeferred: (Int) -> Void
    @Bindable var viewModel: RawCullViewModel

    private var isReviewed: Bool {
        analysis?.reviewState == .reviewed
    }

    private var isDeferred: Bool {
        analysis?.reviewState == .deferred
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Burst \(groupNumber.formatted(.number.precision(.integerLength(2))))")
                    .font(.headline)
                Text("\(files.count) frames")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button {
                viewModel.compareBurstGroup(files)
            } label: {
                Label("Open burst", systemImage: "arrow.right")
            }
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .help("Open this burst for review")

            if let groupID = analysis?.groupID {
                Button {
                    onReviewed(groupID)
                } label: {
                    Label("Mark Reviewed", systemImage: isReviewed ? "checkmark.circle.fill" : "checkmark.circle")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(isReviewed ? .green : nil)
                .help("Mark this burst as reviewed")
                .accessibilityValue(isReviewed ? "Selected" : "Not selected")

                Button {
                    onDeferred(groupID)
                } label: {
                    Label("Defer", systemImage: isDeferred ? "clock.badge.checkmark.fill" : "clock.arrow.circlepath")
                }
                .controlSize(.regular)
                .buttonStyle(.bordered)
                .tint(isDeferred ? .orange : nil)
                .help("Defer this burst for later review")
                .accessibilityValue(isDeferred ? "Selected" : "Not selected")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct BatchBadgeSelectionItem: Identifiable {
    var id: String {
        label
    }

    let label: String
    let count: Int
    let color: Color
}

private struct BatchBadgeSelectionControlsView: View {
    let items: [BatchBadgeSelectionItem]
    let selectedCount: Int
    @Binding var rating: Int
    let onSelectBadge: (String) -> Void
    let onApplyRating: () -> Void

    private let ratings: [(value: Int, label: String)] = [
        (-1, "X"),
        (0, "P"),
        (2, "2"),
        (3, "3"),
        (4, "4"),
        (5, "5")
    ]

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(items, id: \.id) { item in
                        Button {
                            onSelectBadge(item.label)
                        } label: {
                            Text("\(item.label) \(item.count)")
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(item.color)
                        // swiftformat:disable:next isEmpty
                        // swiftlint:disable:next empty_count
                        .disabled(item.count == 0)
                        .help("Select \(item.count) visible thumbnails tagged \(item.label). Hold Command to add or remove from the current selection.")
                    }
                }
                .padding(.vertical, 1)
            }
            .frame(maxWidth: 360)

            Text("\(selectedCount) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 72, alignment: .trailing)

            Picker("Rating", selection: $rating) {
                ForEach(ratings, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 150)
            .help("Rating to apply to the selected thumbnails")

            Button("Apply") {
                onApplyRating()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
            .disabled(selectedCount == 0)
            .help("Apply the selected rating to the selected thumbnails")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Badge batch selection")
    }
}

// MARK: - CullingGridView

struct CullingGridView<Header: View>: View {
    @Bindable var viewModel: RawCullViewModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature
    @ViewBuilder let header: () -> Header
    var batchBadgeSelectionEnabled: () -> Bool = { false }

    @State private var ratingFilter: GridRatingFilter = .all
    @State private var batchRating: Int = 3

    private var projection: CullingGridProjection {
        viewModel.cullingGridProjection(ratingFilter: ratingFilter)
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
                        selectedCount: viewModel.selectedFileIDs.count,
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

            if viewModel.showsBurstGroups {
                HStack(spacing: 14) {
                    Button {
                        viewModel.similarityFeature.burstModeActive = false
                    } label: {
                        Label("Burst Groups", systemImage: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)

                    Text(reviewQueueTitle)
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("\(visibleBurstGroups.count) bursts visible")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·  pick of burst highlighted")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }

            ZStack {
                // Grid view
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if viewModel.showsBurstGroups {
                                LazyVStack(spacing: 16) {
                                    ForEach(renderedBurstGroups) { group in
                                        burstGroupCard(group, number: burstNumber(for: group.id))
                                    }
                                }
                            } else {
                                LazyVGrid(
                                    columns: [GridItem(.adaptive(minimum: CGFloat(200)), spacing: 12)],
                                    spacing: 12,
                                ) {
                                    // ── Flat mode (default) ───────────────────────────
                                    ForEach(files, id: \.id) { file in
                                        ImageItemView(
                                            viewModel: viewModel,
                                            file: file,
                                            isSelected: viewModel.selectedFileID == file.id,
                                            isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
                                            thumbnailSize: 200,
                                            ratingValue: ratingValue(for: file),
                                            ratingDisplay: ratingDisplay(for: file),
                                            ratingColor: ratingColor(for: file),
                                            semanticResultRank: semanticResultRank(
                                                for: file,
                                            ),
                                            semanticResultCount: semanticResultCount,
                                            semanticResultScore: semanticResultScore(
                                                for: file,
                                            ),
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
                        guard let id = viewModel.selectedFileID else { return }
                        // Defer one runloop cycle so LazyVGrid has laid out before scrolling
                        Task { @MainActor in
                            proxy.scrollTo(id, anchor: .top)
                        }
                    }
                    .onChange(of: viewModel.selectedFileID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                    .onChange(of: sortScrollState) { _, newState in
                        guard let selectedID = CullingGridSelectionCoordinator.scrollTargetAfterSortChange(
                            state: newState,
                            selectedFileID: viewModel.selectedFileID,
                            showsBurstGroups: viewModel.showsBurstGroups,
                        ) else { return }

                        // Let LazyVGrid apply the new ordering before locating the selected cell.
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(selectedID, anchor: .center)
                            }
                        }
                    }
                }

                CullingGridProgressOverlay(
                    viewModel: viewModel,
                    similarityFeature: similarityFeature,
                )
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showsBurstGroups)
        .animation(.easeInOut(duration: 0.15), value: ratingFilter)
        .task(id: viewModel.selectedSource) {
            await ThumbnailLoader.shared.cancelAll()
        }
        .onChange(of: gridCacheKey, initial: true) { _, _ in
            recomputeGridCache()
        }
        .thumbnailKeyNavigation(
            viewModel: viewModel,
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
        viewModel.selectedFileID = file.id
        viewModel.openZoomOverlay(navigationIDs: zoomNavigationIDs(for: file))
    }

    private func selectFiles(matchingBadge badge: String) {
        let matchingIDs = CullingGridSelectionCoordinator.matchingIDs(
            forBadge: badge,
            visibleFiles: visibleSelectionFiles,
            burstGroupLookup: viewModel.similarityFeature.burstGroupLookup,
            burstAnalysisResults: viewModel.burstAnalysisResults,
            saliencyInfo: viewModel.sharpnessModel.saliencyInfo,
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
        let selectedIDs = viewModel.selectedFileIDs
        guard !selectedIDs.isEmpty else { return }
        let selectedFiles = CullingGridSelectionCoordinator.actionFiles(
            requestedIDs: selectedIDs,
            renderedFiles: visibleSelectionFiles,
        )
        guard !selectedFiles.isEmpty else { return }
        viewModel.updateRating(for: selectedFiles, rating: batchRating)
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
            showsBurstGroups: viewModel.showsBurstGroups,
            visibleBurstGroups: renderedBurstGroups,
            files: files,
        )
    }

    private var badgeSelectionItems: [BatchBadgeSelectionItem] {
        projection.badges
    }

    private var selectionState: CullingGridSelectionState {
        CullingGridSelectionState(
            selectedFileID: viewModel.selectedFileID,
            selectedFileIDs: viewModel.selectedFileIDs,
        )
    }

    private func applySelectionState(_ state: CullingGridSelectionState) {
        viewModel.selectedFileID = state.selectedFileID
        viewModel.selectedFileIDs = state.selectedFileIDs
    }

    private func synchronizeSelectionWithRenderedFiles() {
        let renderedIDs = visibleSelectionIDs
        viewModel.cullingGridRenderedFileIDs = renderedIDs
        applySelectionState(CullingGridSelectionCoordinator.reconcileSelection(
            selectionState,
            visibleIDs: renderedIDs,
        ))
    }

    // MARK: - Burst grouping helpers

    private var gridCacheKey: CullingGridProjectionKey {
        projection.key
    }

    private func recomputeGridCache() {
        synchronizeSelectionWithRenderedFiles()
    }

    private var reviewQueueTitle: String {
        switch viewModel.burstReviewQueueFilter {
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

    /// Builds the thumbnail cell for a file inside a burst group.
    /// Extracted into a helper so the `@ViewBuilder` closure in the `ForEach` remains
    /// simple enough for Swift's type-checker.
    private func burstCell(file: FileItem) -> some View {
        ImageItemView(
            viewModel: viewModel,
            file: file,
            isSelected: viewModel.selectedFileID == file.id,
            isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
            thumbnailSize: 200,
            ratingValue: ratingValue(for: file),
            ratingDisplay: ratingDisplay(for: file),
            ratingColor: ratingColor(for: file),
            onSelect: { handleToggleSelection(for: file) },
            onDoubleSelect: { handleDoubleSelect(for: file) },
        )
    }

    private func burstGroupCard(_ group: CullingGridVisibleBurstGroup, number: Int) -> some View {
        let analysis = viewModel.burstAnalysisResult(for: group.id)

        return VStack(alignment: .leading, spacing: 0) {
            if group.files.count > 1 {
                BurstGroupHeaderView(
                    groupNumber: number,
                    files: group.files,
                    analysis: analysis,
                    onReviewed: markBurstGroupReviewed,
                    onDeferred: deferBurstGroup,
                    viewModel: viewModel,
                )
            }

            Divider()
            ScrollView(.horizontal) {
                // An eager stack gives the horizontal scroll view a stable intrinsic
                // height while its card is hosted in the outer LazyVStack. A nested
                // LazyHStack can remain unrealized and collapse the row to its header.
                HStack(spacing: 12) {
                    ForEach(group.files, id: \.id) { file in
                        burstCell(file: file)
                            .id(file.id)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }

    private func markBurstGroupReviewed(_ groupID: Int) {
        viewModel.toggleBurstGroupReviewed(groupID: groupID)
    }

    private func deferBurstGroup(_ groupID: Int) {
        viewModel.toggleBurstGroupDeferred(groupID: groupID)
    }

    private func handleBurstKeyPress(_ characters: String) -> KeyPress.Result {
        guard viewModel.showsBurstGroups else { return .ignored }
        if characters == "\u{1b}" {
            viewModel.similarityFeature.burstModeActive = false
            return .handled
        }
        if characters == "u" || characters == "U" {
            viewModel.undoLastBurstAction()
            return .handled
        }
        guard let groupFiles = currentBurstGroupFiles
        else { return .ignored }

        switch characters {
        case "\r":
            viewModel.compareBurstGroup(groupFiles)
            return .handled

        case "B", "b":
            guard canApplyOneClickCulling(to: groupFiles) else { return .ignored }
            viewModel.keepBestInGroup(from: groupFiles)
            return .handled

        case "2":
            guard canApplyOneClickCulling(to: groupFiles) else { return .ignored }
            viewModel.keepTopTwoInGroup(from: groupFiles)
            return .handled

        default:
            return .ignored
        }
    }

    private var currentBurstGroupFiles: [FileItem]? {
        guard let selectedID = viewModel.selectedFileID,
              let groupID = viewModel.similarityFeature.burstGroupLookup[selectedID]
        else { return nil }
        return renderedBurstGroups.first { $0.id == groupID }?.files
    }

    private func canApplyOneClickCulling(to groupFiles: [FileItem]) -> Bool {
        guard let groupID = groupFiles.lazy.compactMap({ viewModel.similarityFeature.burstGroupLookup[$0.id] }).first,
              let result = viewModel.burstAnalysisResult(for: groupID)
        else { return false }
        return result.canApplyOneClickCulling(hasSharpnessScores: hasSharpnessScoresSnapshot)
    }

    // MARK: - Rating filter

    var files: [FileItem] {
        projection.files
    }

    private var sortScrollState: CullingGridSortScrollState {
        CullingGridSortScrollState(
            isSharpnessSortingActive: viewModel.sharpnessModel.sortBySharpness,
            isSimilaritySortingActive: similarityFeature.isSimilaritySortingActive,
            orderedFileIDs: projection.fileIDs,
        )
    }

    private var semanticResultCount: Int? {
        guard !viewModel.showsBurstGroups,
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

    private func ratingValue(for file: FileItem) -> Int {
        viewModel.getRating(for: file)
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: ratingValue(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func ratingColor(for file: FileItem) -> Color? {
        switch ratingValue(for: file) {
        case -1: .red
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: nil
        }
    }
}
