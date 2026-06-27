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
import OSLog
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
    let files: [FileItem]
    let analysis: BurstAnalysisResult?
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        HStack(spacing: 3) {
            Button("Open burst") {
                viewModel.compareBurstGroup(files)
            }
            .controlSize(.mini)
            .buttonStyle(.borderedProminent)
            .help("Open this burst for review")

            if let groupID = analysis?.groupID {
                Button("Reviewed") {
                    viewModel.markBurstGroupReviewed(groupID: groupID)
                }
                .controlSize(.mini)
                .help("Mark this burst as reviewed")

                Button("Defer") {
                    viewModel.deferBurstGroup(groupID: groupID)
                }
                .controlSize(.mini)
                .help("Defer this burst for later review")
            }

            Spacer(minLength: 6)
        }
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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
    @ViewBuilder let header: () -> Header
    var batchBadgeSelectionEnabled: () -> Bool = { false }

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all
    @State private var batchRating: Int = 3

    // ── Burst-mode render cache ──────────────────────────────────────────
    // Recomputed only when `gridCacheKey` changes, so hover/selection
    // invalidations do not rebuild these O(n) / O(m·k) structures.
    @State private var visibleBurstGroups: [CullingGridVisibleBurstGroup] = []
    @State private var hasSharpnessScoresSnapshot: Bool = false

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
            .padding()
            .background(Color.gray.opacity(0.1))

            ZStack {
                // Grid view
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: CGFloat(200)), spacing: 12)
                            ],
                            spacing: 12,
                        ) {
                            if viewModel.showsBurstGroups {
                                // ── Burst grouping mode ───────────────────────────
                                ForEach(visibleBurstGroups) { vg in
                                    Section {
                                        ForEach(vg.files, id: \.id) { file in
                                            burstCell(file: file)
                                                .id(file.id)
                                                .onHover { isHovering in
                                                    hoveredFileID = isHovering ? file.id : nil
                                                }
                                        }
                                    } header: {
                                        if vg.files.count > 1 {
                                            BurstGroupHeaderView(
                                                files: vg.files,
                                                analysis: viewModel.burstAnalysisResult(for: vg.id),
                                                viewModel: viewModel,
                                            )
                                            .padding(.top, 4)
                                        }
                                    }
                                }
                            } else {
                                // ── Flat mode (default) ───────────────────────────
                                ForEach(files, id: \.id) { file in
                                    ImageItemView(
                                        viewModel: viewModel,
                                        file: file,
                                        isHovered: hoveredFileID == file.id,
                                        isSelected: viewModel.selectedFileID == file.id,
                                        isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
                                        thumbnailSize: 200,
                                        ratingValue: ratingValue(for: file),
                                        ratingDisplay: ratingDisplay(for: file),
                                        ratingColor: ratingColor(for: file),
                                        onSelect: { handleToggleSelection(for: file) },
                                        onDoubleSelect: { handleDoubleSelect(for: file) },
                                    )
                                    .id(file.id)
                                    .onHover { isHovered in
                                        hoveredFileID = isHovered ? file.id : nil
                                    }
                                }
                            }
                        }
                        .padding()
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
                }

                CullingGridProgressOverlay(viewModel: viewModel)
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: viewModel.sharpnessModel.isScoring)
        .animation(.easeInOut(duration: 0.2), value: viewModel.similarityModel.isIndexing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.similarityModel.isGrouping)
        .animation(.easeInOut(duration: 0.15), value: viewModel.showsBurstGroups)
        .animation(.easeInOut(duration: 0.15), value: ratingFilter)
        .toolbar { sharedSelectionStatusToolbar }
        .onKeyPress(characters: CharacterSet(charactersIn: "\rBb2RrUu")) { press in
            handleBurstKeyPress(press.characters)
        }
        .onKeyPress(.escape) {
            if viewModel.showsBurstGroups {
                viewModel.similarityModel.burstModeActive = false
                return .handled
            }
            return .ignored
        }
        .task(id: viewModel.selectedSource) {
            viewModel.selectedFileIDs = []
            await ThumbnailLoader.shared.cancelAll()
        }
        .onChange(of: gridCacheKey, initial: true) { _, _ in
            recomputeGridCache()
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .grid)
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
            burstGroupLookup: viewModel.similarityModel.burstGroupLookup,
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
        let selectedFiles = visibleSelectionFiles.filter { selectedIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }
        viewModel.updateRating(for: selectedFiles, rating: batchRating)
    }

    private var visibleSelectionFiles: [FileItem] {
        if viewModel.showsBurstGroups {
            return visibleBurstGroups.flatMap(\.files)
        }
        return files
    }

    private var visibleSelectionIDs: [FileItem.ID] {
        if viewModel.showsBurstGroups {
            return visibleBurstGroups.flatMap { group in
                group.files.map(\.id)
            }
        }
        return files.map(\.id)
    }

    private func zoomNavigationIDs(for file: FileItem) -> [FileItem.ID] {
        CullingGridSelectionCoordinator.zoomNavigationIDs(
            for: file,
            showsBurstGroups: viewModel.showsBurstGroups,
            visibleBurstGroups: visibleBurstGroups,
            files: files,
        )
    }

    private var badgeSelectionItems: [BatchBadgeSelectionItem] {
        CullingGridSelectionCoordinator.badgeSelectionItems(
            visibleFiles: visibleSelectionFiles,
            burstGroupLookup: viewModel.similarityModel.burstGroupLookup,
            burstAnalysisResults: viewModel.burstAnalysisResults,
            saliencyInfo: viewModel.sharpnessModel.saliencyInfo,
        )
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

    // MARK: - Burst grouping helpers

    private var gridCacheKey: CullingGridRenderCacheKey {
        CullingGridRenderCacheKey(
            burstGroups: reviewFilteredBurstGroups,
            files: files,
            ratingFilter: ratingFilter,
            reviewQueueFilter: viewModel.burstReviewQueueFilter,
            scoresCount: viewModel.sharpnessModel.scores.count,
            scoreRevision: viewModel.sharpnessModel.scoreRevision,
            maxScore: viewModel.sharpnessModel.maxScore,
            burstAnalysisResults: viewModel.burstAnalysisResults,
        )
    }

    private func recomputeGridCache() {
        let cache = CullingGridRenderCache.rebuild(
            files: files,
            burstGroups: reviewFilteredBurstGroups,
            scores: viewModel.sharpnessModel.scores,
        )
        visibleBurstGroups = cache.visibleBurstGroups
        hasSharpnessScoresSnapshot = cache.hasSharpnessScoresSnapshot
    }

    private var reviewFilteredBurstGroups: [BurstGroup] {
        viewModel.filteredBurstGroupsForReviewQueue
    }

    /// Builds the thumbnail cell for a file inside a burst group.
    /// Extracted into a helper so the `@ViewBuilder` closure in the `ForEach` remains
    /// simple enough for Swift's type-checker.
    private func burstCell(file: FileItem) -> some View {
        ImageItemView(
            viewModel: viewModel,
            file: file,
            isHovered: hoveredFileID == file.id,
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

    private func handleBurstKeyPress(_ characters: String) -> KeyPress.Result {
        guard viewModel.showsBurstGroups,
              let groupFiles = currentBurstGroupFiles
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

        case "U", "u":
            viewModel.undoLastBurstAction()
            return .handled

        default:
            return .ignored
        }
    }

    private var currentBurstGroupFiles: [FileItem]? {
        guard let selectedID = viewModel.selectedFileID,
              let groupID = viewModel.similarityModel.burstGroupLookup[selectedID]
        else { return nil }
        return visibleBurstGroups.first { $0.id == groupID }?.files
    }

    private func canApplyOneClickCulling(to groupFiles: [FileItem]) -> Bool {
        guard let groupID = groupFiles.lazy.compactMap({ viewModel.similarityModel.burstGroupLookup[$0.id] }).first,
              let result = viewModel.burstAnalysisResult(for: groupID)
        else { return false }
        return result.canApplyOneClickCulling(hasSharpnessScores: hasSharpnessScoresSnapshot)
    }

    // MARK: - Rating filter

    var files: [FileItem] {
        switch ratingFilter {
        case .all:
            return viewModel.filteredFiles

        case .unrated:
            guard let catalog = viewModel.selectedSource?.url else { return viewModel.filteredFiles }
            return viewModel.filteredFiles.filter { !viewModel.cullingModel.isUnrated(photo: $0.name, in: catalog) }

        case .rating(0):
            return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) == 0 }

        case let .rating(n):
            return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) == n }
        }
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

// MARK: - Toolbar

extension CullingGridView {
    @ToolbarContentBuilder
    var sharedSelectionStatusToolbar: some ToolbarContent {
        if viewModel.selectedFileIDs.count > 1 {
            ToolbarItem(placement: .status) {
                Text("\(viewModel.selectedFileIDs.count) selected — press a rating key to apply")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
