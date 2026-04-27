//
//  SimilarityGridSelectionView.swift
//  RawCull
//
//  Similarity-focused grid. Header exposes only similarity indexing and
//  burst grouping. A toolbar toggle (default ON) gates an automatic
//  sharpness-scoring prerequisite that runs the first time any analysis
//  action is invoked while scores are missing.
//

import AppKit
import OSLog
import SwiftUI

// MARK: - BurstGroupHeaderView

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

struct SimilarityGridSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all
    @State private var autoSharpnessScoring: Bool = true

    // Debounced regroup task for the burst-sensitivity slider — mirrors
    // SimilarityControlsView so dragging the slider collapses to a single
    // regroup call ~200 ms after the drag stops.
    @State private var pendingRegroupTask: Task<Void, Never>?

    // Burst-mode render cache (same invalidation semantics as
    // GridThumbnailSelectionView.gridCacheKey).
    @State private var visibleBurstGroups: [VisibleBurstGroup] = []
    @State private var bestInGroup: [Int: BestInGroupInfo] = [:]
    @State private var hasSharpnessScoresSnapshot: Bool = false

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header — similarity & burst controls only.
            HStack(spacing: 10) {
                similarityHeaderControls
                Spacer()
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            ZStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: CGFloat(200)), spacing: 12)
                            ],
                            spacing: 12,
                        ) {
                            if viewModel.similarityModel.burstModeActive {
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

    // MARK: - Inline similarity controls (with auto-scoring prerequisite)

    @ViewBuilder
    private var similarityHeaderControls: some View {
        let hasEmbeddings = !viewModel.similarityModel.embeddings.isEmpty
        let isIndexing = viewModel.similarityModel.isIndexing
        let isGrouping = viewModel.similarityModel.isGrouping
        let inBurstMode = viewModel.similarityModel.burstModeActive

        if !inBurstMode {
            Button {
                runWithAutoScoring { await viewModel.indexSimilarity() }
            } label: {
                if isIndexing {
                    Label("Indexing…", systemImage: "wand.and.sparkles")
                } else if hasEmbeddings {
                    Label("Re-index", systemImage: "wand.and.sparkles")
                } else {
                    Label("Index Similarity", systemImage: "wand.and.sparkles")
                }
            }
            .font(.caption)
            .disabled(isIndexing || viewModel.files.isEmpty)
            .help("Compute visual feature embeddings for all images in this catalog")

            if isIndexing {
                Button(role: .cancel) {
                    viewModel.similarityModel.cancelIndexing()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .font(.caption)
                .tint(.red)
                .help("Abort similarity indexing and discard partial results")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            if hasEmbeddings, !isIndexing {
                Button {
                    runWithAutoScoring { await viewModel.findSimilarToSelected() }
                } label: {
                    Label("Find Similar", systemImage: "photo.stack")
                }
                .font(.caption)
                .disabled(viewModel.selectedFile == nil)
                .help("Rank all images by visual similarity to the selected image")

                if !viewModel.similarityModel.distances.isEmpty {
                    Toggle(isOn: $viewModel.similarityModel.sortBySimilarity) {
                        Label("Similarity", systemImage: "arrow.up.arrow.down")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                    .help("Sort thumbnails by similarity to selected image (most similar first)")
                    .onChange(of: viewModel.similarityModel.sortBySimilarity) { _, _ in
                        Task(priority: .background) {
                            await viewModel.handleSortOrderChange()
                        }
                    }
                }

                Divider().frame(height: 16)
            }
        }

        if !isIndexing {
            if inBurstMode {
                HStack(spacing: 4) {
                    Slider(
                        value: $viewModel.similarityModel.burstSensitivity,
                        in: 0.05 ... 0.60,
                    )
                    .frame(width: 70)
                    .help("Burst sensitivity — lower = tighter groups, higher = similar scenes grouped together")
                    .onChange(of: viewModel.similarityModel.burstSensitivity) { _, _ in
                        pendingRegroupTask?.cancel()
                        pendingRegroupTask = Task {
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            if Task.isCancelled { return }
                            await viewModel.reGroupBursts()
                        }
                    }
                    Text(
                        String(
                            format: "%.2f · %d groups",
                            viewModel.similarityModel.burstSensitivity,
                            viewModel.similarityModel.burstGroups.count,
                        ),
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 84, alignment: .leading)
                }

                Button {
                    viewModel.similarityModel.burstModeActive = false
                } label: {
                    Label("Exit Groups", systemImage: "xmark.circle")
                }
                .font(.caption)
                .help("Return to flat grid view")
            } else {
                Button {
                    runWithAutoScoring { await viewModel.indexAndGroupBursts() }
                } label: {
                    if isGrouping {
                        Label("Grouping…", systemImage: "square.stack.3d.up")
                    } else if hasEmbeddings {
                        Label("Group Bursts", systemImage: "square.stack.3d.up")
                    } else {
                        Label("Index + Group Bursts", systemImage: "square.stack.3d.up")
                    }
                }
                .font(.caption)
                .disabled(isGrouping || viewModel.files.isEmpty)
                .help(
                    hasEmbeddings
                        ? "Cluster consecutive similar frames into burst groups"
                        : "Index all images then cluster into burst groups",
                )
            }
        }

        // Spinner shown while calibrating is in progress
        if viewModel.sharpnessModel.isCalibratingSharpnessScoring {
            HStack {
                ProgressView()
                Text("Calibrating sharpness scoring, please wait...")
            }
        }
    }

    /// Runs `action` after first computing sharpness scores when the toggle
    /// is on and scores are missing. Re-runs are skipped — `scoreFiles`
    /// already guards `!isScoring` and `scores` is reset on each run, so
    /// this is safe even if the user fires multiple buttons in quick
    /// succession.
    private func runWithAutoScoring(_ action: @escaping @MainActor () async -> Void) {
        Task {
            if autoSharpnessScoring, viewModel.sharpnessModel.scores.isEmpty {
                await viewModel.calibrateAndScoreCurrentCatalog()
            }
            await action()
        }
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
        viewModel.zoomOverlayVisible = true
    }

    // MARK: - Burst grouping helpers

    private struct VisibleBurstGroup: Identifiable {
        let id: Int
        let files: [FileItem]
    }

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

extension SimilarityGridSelectionView {
    @ToolbarContentBuilder
    var gridToolbar: some ToolbarContent {
        ToolbarItem(placement: .status) {
            Toggle(isOn: $autoSharpnessScoring) {
                Label("Auto Sharpness", systemImage: "scope")
            }
            .toggleStyle(.button)
            .help("Auto-run sharpness scoring before similarity actions when scores are missing")
        }

        if viewModel.selectedFileIDs.count > 1 {
            ToolbarItem(placement: .status) {
                Text("\(viewModel.selectedFileIDs.count) selected — press a rating key to apply")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
    }
}
