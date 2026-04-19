//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import AppKit
import OSLog
import SwiftUI

// MARK: - BurstGroupHeaderView

/// Renders a single burst-group section header. All sharpness math is done
/// upstream (see `GridCache` in the grid view) and passed in as `best` so
/// the header body never walks the group's files or reads `maxScore` during
/// redraw.
private struct BurstGroupHeaderView: View {
    let files: [FileItem]
    let best: BestInGroupInfo?
    let hasSharpnessScores: Bool
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Burst · \(files.count) frames", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let best {
                    if let pct = best.percent {
                        Text("Best: \(best.fileName) (\(pct)%)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Best: \(best.fileName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Keep Best") {
                    viewModel.keepBestInGroup(from: files)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.caption)
                .controlSize(.mini)
                .disabled(!hasSharpnessScores)
                .help(
                    hasSharpnessScores
                        ? "Rate sharpest frame ★★★ and reject all others"
                        : "Run sharpness scoring first to identify the best frame",
                )

                Button("Reject All") {
                    viewModel.updateRating(for: files, rating: -1)
                }
                .font(.caption)
                .controlSize(.mini)
                .foregroundStyle(.red)
                .help("Reject all frames in this burst group")
            }

            if !hasSharpnessScores {
                Text("Run Sharpness Scoring to enable Keep Best")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: -

enum GridRatingFilter: Hashable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}

struct GridThumbnailSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all
    @State private var sharpnessThreshold: Int = 50

    // ── Burst-mode render cache ──────────────────────────────────────────
    // Recomputed only when `gridCacheKey` changes, so hover/selection
    // invalidations do not rebuild these O(n) / O(m·k) structures.
    @State private var visibleBurstGroups: [VisibleBurstGroup] = []
    @State private var bestInGroup: [Int: BestInGroupInfo] = [:]
    @State private var hasSharpnessScoresSnapshot: Bool = false

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header — Row 1: analysis tools, Row 2: culling/rating filters
            // Row 1 — Analysis tools (sharpness hidden in burst mode)
            HStack(spacing: 10) {
                if !viewModel.similarityModel.burstModeActive {
                    SharpnessControlsView(viewModel: viewModel, sharpnessThreshold: $sharpnessThreshold)

                    Divider().frame(height: 20)
                }

                SimilarityControlsView(viewModel: viewModel)

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
                            if viewModel.similarityModel.burstModeActive {
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
                                                best: bestInGroup[vg.id],
                                                hasSharpnessScores: hasSharpnessScoresSnapshot,
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
                                        isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
                                        thumbnailSize: 200,
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

                // Progress view — shown during sharpness scoring
                if viewModel.sharpnessModel.isScoring {
                    ProgressCount(
                        progress: Binding(
                            get: { Double(viewModel.sharpnessModel.scoringProgress) },
                            set: { _ in },
                        ),
                        estimatedSeconds: Binding(
                            get: { viewModel.sharpnessModel.scoringEstimatedSeconds },
                            set: { _ in },
                        ),
                        max: Double(viewModel.sharpnessModel.scoringTotal),
                        statusText: "Scoring sharpness…",
                    )
                    .frame(maxWidth: 480)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1),
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                // Progress view — shown during burst grouping
                if viewModel.similarityModel.isGrouping {
                    Text("Grouping bursts…")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1),
                        )
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                        .transition(.scale(scale: 0.95).combined(with: .opacity))
                }

                // Progress view — shown during similarity indexing
                if viewModel.similarityModel.isIndexing {
                    ProgressCount(
                        progress: Binding(
                            get: { Double(viewModel.similarityModel.indexingProgress) },
                            set: { _ in },
                        ),
                        estimatedSeconds: Binding(
                            get: { viewModel.similarityModel.indexingEstimatedSeconds },
                            set: { _ in },
                        ),
                        max: Double(viewModel.similarityModel.indexingTotal),
                        statusText: "Indexing similarity…",
                    )
                    .frame(maxWidth: 480)
                    .padding(16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1),
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: viewModel.sharpnessModel.isScoring)
        .animation(.easeInOut(duration: 0.2), value: viewModel.similarityModel.isIndexing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.similarityModel.isGrouping)
        .animation(.easeInOut(duration: 0.15), value: viewModel.similarityModel.burstModeActive)
        .animation(.easeInOut(duration: 0.15), value: ratingFilter)
        .toolbar { gridToolbar }
        .task(id: viewModel.selectedSource) {
            viewModel.selectedFileIDs = []
            await ThumbnailLoader.shared.cancelAll()
        }
        .onChange(of: gridCacheKey, initial: true) { _, _ in
            recomputeGridCache()
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .grid)
    }

    private func handleToggleSelection(for file: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if viewModel.selectedFileIDs.contains(file.id) {
                viewModel.selectedFileIDs.remove(file.id)
            } else {
                viewModel.selectedFileIDs.insert(file.id)
                if let anchor = viewModel.selectedFileID {
                    viewModel.selectedFileIDs.insert(anchor)
                }
            }
            viewModel.selectedFileID = file.id
        } else if flags.contains(.shift), let anchorID = viewModel.selectedFileID {
            let ids = files.map(\.id)
            if let from = ids.firstIndex(of: anchorID),
               let to = ids.firstIndex(of: file.id) {
                let range = from <= to ? from ... to : to ... from
                viewModel.selectedFileIDs = Set(ids[range])
            }
        } else {
            viewModel.selectedFileIDs = []
            viewModel.selectedFileID = file.id
        }
    }

    private func handleDoubleSelect(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.zoomExtractionTask?.cancel()
        viewModel.zoomExtractionTask = ZoomPreviewHandler.handleOverlay(
            file: file,
            useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
            viewModel: viewModel,
        )
    }

    // MARK: - Burst grouping helpers

    /// A burst group reduced to only the files currently visible (post rating-filter).
    private struct VisibleBurstGroup: Identifiable {
        let id: Int
        let files: [FileItem]
    }

    /// Cheap content signature for the burst-mode render cache. Changes in
    /// any of these fields invalidate `visibleBurstGroups` and
    /// `bestInGroup`; unrelated mutations (hover, selection, progress text)
    /// do not.
    /// All stored properties are read via synthesized Hashable when the
    /// struct drives `.onChange(of: gridCacheKey)` above; Periphery does
    /// not see synthesized conformances as reads, hence the ignores.
    private struct GridCacheKey: Hashable {
        // periphery:ignore
        let burstGroupsCount: Int
        // periphery:ignore
        let burstStructureHash: Int
        // periphery:ignore
        let filesCount: Int
        // periphery:ignore
        let filesFirstID: UUID?
        // periphery:ignore
        let filesLastID: UUID?
        // periphery:ignore
        let ratingFilter: GridRatingFilter
        // periphery:ignore
        let scoresCount: Int
    }

    private var gridCacheKey: GridCacheKey {
        let groups = viewModel.similarityModel.burstGroups
        var structureHasher = Hasher()
        for g in groups {
            structureHasher.combine(g.id)
            structureHasher.combine(g.fileIDs.count)
        }
        let currentFiles = files
        return GridCacheKey(
            burstGroupsCount: groups.count,
            burstStructureHash: structureHasher.finalize(),
            filesCount: currentFiles.count,
            filesFirstID: currentFiles.first?.id,
            filesLastID: currentFiles.last?.id,
            ratingFilter: ratingFilter,
            scoresCount: viewModel.sharpnessModel.scores.count,
        )
    }

    /// Rebuild the burst-mode render cache. Reads `maxScore` exactly once
    /// (it is an O(n log n) computed property) and walks each burst group
    /// a single time for both the visible-filter and best-in-group passes.
    private func recomputeGridCache() {
        let currentFiles = files
        let lookup = Dictionary(uniqueKeysWithValues: currentFiles.map { ($0.id, $0) })
        let scores = viewModel.sharpnessModel.scores
        let maxScore = viewModel.sharpnessModel.maxScore

        var newVisible: [VisibleBurstGroup] = []
        newVisible.reserveCapacity(viewModel.similarityModel.burstGroups.count)
        var newBest: [Int: BestInGroupInfo] = [:]

        for group in viewModel.similarityModel.burstGroups {
            let visible = group.fileIDs.compactMap { lookup[$0] }
            guard !visible.isEmpty else { continue }
            newVisible.append(VisibleBurstGroup(id: group.id, files: visible))
            if let info = RawCullViewModel.bestInGroupInfo(
                files: visible,
                scores: scores,
                maxScore: maxScore,
            ) {
                newBest[group.id] = info
            }
        }

        visibleBurstGroups = newVisible
        bestInGroup = newBest
        hasSharpnessScoresSnapshot = !scores.isEmpty
    }

    /// Builds the thumbnail cell for a file inside a burst group.
    /// Extracted into a helper so the `@ViewBuilder` closure in the `ForEach` remains
    /// simple enough for Swift's type-checker, while `isBestInGroup` is still an explicit
    /// parameter of `ImageItemView` (guaranteeing SwiftUI re-renders the cell when it changes).
    private func burstCell(file: FileItem) -> some View {
        ImageItemView(
            viewModel: viewModel,
            file: file,
            isHovered: hoveredFileID == file.id,
            isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
            thumbnailSize: 200,
            onSelect: { handleToggleSelection(for: file) },
            onDoubleSelect: { handleDoubleSelect(for: file) },
        )
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
}

// MARK: - Toolbar

extension GridThumbnailSelectionView {
    @ToolbarContentBuilder
    var gridToolbar: some ToolbarContent {
        if viewModel.selectedFileIDs.count > 1 {
            ToolbarItem(placement: .status) {
                Text("\(viewModel.selectedFileIDs.count) selected — press a rating key to apply")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
