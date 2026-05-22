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
import SwiftUI

// MARK: - Rating filter

enum GridRatingFilter: Hashable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}

// MARK: - Burst-group section header

/// Renders a single burst-group section header. All sharpness math is done
/// upstream (see `recomputeGridCache` in `CullingGridView`) and passed in as
/// `best` so the header body never walks the group's files or reads
/// `maxScore` during redraw.
private struct BurstGroupHeaderView: View {
    let files: [FileItem]
    let best: BestInGroupInfo?
    let analysis: BurstAnalysisResult?
    let hasSharpnessScores: Bool
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Burst · \(files.count) frames", systemImage: "square.stack.3d.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let analysis {
                    ConfidenceBadgeView(confidence: analysis.confidence)
                }

                if let best {
                    Text(bestLabel(best))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                actionButtons
            }

            if let analysis {
                HStack(spacing: 6) {
                    ForEach(Array(analysis.reasons.prefix(3)), id: \.self) { reason in
                        Text(reason)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(analysis.cautions.prefix(2)), id: \.self) { caution in
                        Text(caution)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
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

    @ViewBuilder
    private var actionButtons: some View {
        let confidence = analysis?.confidence ?? .low

        if confidence == .high {
            keepBestButton(prominent: true)
            compareButton(title: "Compare")
            keepTopTwoButton(prominent: false)
        } else if confidence == .medium {
            compareButton(title: "Compare Top 2", prominent: true)
            keepTopTwoButton(prominent: false)
            keepBestButton(prominent: false)
        } else {
            compareButton(title: "Compare")
        }

        if viewModel.lastBurstUndoEntry?.groupID == analysis?.groupID {
            Button("Undo") {
                viewModel.undoLastBurstAction()
            }
            .font(.caption)
            .controlSize(.mini)
            .help("Undo the last burst action")
        }
    }

    @ViewBuilder
    private func keepBestButton(prominent: Bool) -> some View {
        if prominent {
            Button("Keep Best") { viewModel.keepBestInGroup(from: files) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .font(.caption)
                .controlSize(.mini)
                .disabled(!hasSharpnessScores)
                .help(hasSharpnessScores ? "Rate best frame ★★★ and reject all others" : "Run analysis first")
        } else {
            Button("Keep Best") { viewModel.keepBestInGroup(from: files) }
                .buttonStyle(.bordered)
                .font(.caption)
                .controlSize(.mini)
                .disabled(!hasSharpnessScores)
                .help(hasSharpnessScores ? "Rate best frame ★★★ and reject all others" : "Run analysis first")
        }
    }

    @ViewBuilder
    private func keepTopTwoButton(prominent: Bool = false) -> some View {
        if prominent {
            Button("Keep Top 2") { viewModel.keepTopTwoInGroup(from: files) }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .controlSize(.mini)
                .disabled(!hasSharpnessScores)
                .help("Rate best frame ★★★, second frame ★★, and reject all others")
        } else {
            Button("Keep Top 2") { viewModel.keepTopTwoInGroup(from: files) }
                .buttonStyle(.bordered)
                .font(.caption)
                .controlSize(.mini)
                .disabled(!hasSharpnessScores)
                .help("Rate best frame ★★★, second frame ★★, and reject all others")
        }
    }

    @ViewBuilder
    private func compareButton(title: String, prominent: Bool = false) -> some View {
        if prominent {
            Button(title) { viewModel.compareBurstGroup(files) }
                .buttonStyle(.borderedProminent)
                .font(.caption)
                .controlSize(.mini)
                .help("Compare the top burst candidates")
        } else {
            Button(title) { viewModel.compareBurstGroup(files) }
                .buttonStyle(.bordered)
                .font(.caption)
                .controlSize(.mini)
                .help("Compare the top burst candidates")
        }
    }

    private func bestLabel(_ best: BestInGroupInfo) -> String {
        let prefix = best.isManualWinner ? "Manual winner" : "Best"
        if let pct = best.percent {
            return "\(prefix): \(best.fileName) (\(pct)%)"
        }
        return "\(prefix): \(best.fileName)"
    }
}

private struct ConfidenceBadgeView: View {
    let confidence: BurstDecisionConfidence

    var body: some View {
        Text(confidence.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
    }

    private var color: Color {
        switch confidence {
        case .high: .green
        case .medium: .orange
        case .low: .gray
        }
    }
}

// MARK: - CullingGridView

struct CullingGridView<Header: View>: View {
    @Bindable var viewModel: RawCullViewModel
    @ViewBuilder let header: () -> Header

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all

    // ── Burst-mode render cache ──────────────────────────────────────────
    // Recomputed only when `gridCacheKey` changes, so hover/selection
    // invalidations do not rebuild these O(n) / O(m·k) structures.
    @State private var visibleBurstGroups: [VisibleBurstGroup] = []
    @State private var bestInGroup: [Int: BestInGroupInfo] = [:]
    @State private var hasSharpnessScoresSnapshot: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                header()
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
                                                analysis: viewModel.burstAnalysisResult(for: vg.id),
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

                // Progress view — shown during indeterminate burst work
                if viewModel.similarityModel.isGrouping || indeterminateBurstAnalysisRunning {
                    HStack(spacing: 10) {
                        ProgressView()
                            .fixedSize()
                        Text(viewModel.burstAnalysisProgress.statusText)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
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
        .toolbar { sharedSelectionStatusToolbar }
        .onKeyPress(characters: CharacterSet(charactersIn: "\rBb2RrUu")) { press in
            handleBurstKeyPress(press.characters)
        }
        .onKeyPress(.escape) {
            if viewModel.similarityModel.burstModeActive {
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

    private var indeterminateBurstAnalysisRunning: Bool {
        viewModel.burstAnalysisProgress.isRunning && !viewModel.burstAnalysisProgress.isCountBased
    }

    // MARK: - Selection handlers

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
            let ids = visibleSelectionIDs
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
        viewModel.openZoomOverlay()
    }

    private var visibleSelectionIDs: [FileItem.ID] {
        if viewModel.similarityModel.burstModeActive {
            return visibleBurstGroups.flatMap { group in
                group.files.map(\.id)
            }
        }
        return files.map(\.id)
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
            if let result = viewModel.burstAnalysisResults[g.id] {
                structureHasher.combine(result.recommendedFileID)
                structureHasher.combine(result.reviewState.rawValue)
            }
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
            if let result = viewModel.burstAnalysisResults[group.id],
               result.reviewState == .manualWinnerOverride,
               let winnerID = result.recommendedFileID,
               let winner = visible.first(where: { $0.id == winnerID }) {
                newBest[group.id] = RawCullViewModel.bestInGroupInfo(
                    file: winner,
                    scores: scores,
                    maxScore: maxScore,
                    isManualWinner: true,
                )
            } else if let info = RawCullViewModel.bestInGroupInfo(
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
    /// simple enough for Swift's type-checker.
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

    private func handleBurstKeyPress(_ characters: String) -> KeyPress.Result {
        guard viewModel.similarityModel.burstModeActive,
              let groupFiles = currentBurstGroupFiles
        else { return .ignored }

        switch characters {
        case "\r":
            viewModel.compareBurstGroup(groupFiles)
            return .handled

        case "B", "b":
            viewModel.keepBestInGroup(from: groupFiles)
            return .handled

        case "2":
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
