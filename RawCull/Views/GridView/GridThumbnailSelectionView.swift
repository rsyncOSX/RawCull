//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import AppKit
import OSLog
import SwiftUI

private enum GridRatingFilter: Equatable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}

struct GridThumbnailSelectionView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.openWindow) private var openWindow

    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all
    @State private var sharpnessThreshold: Int = 50
    @State private var showScanStats = false

    let selectedSource: ARWSourceCatalog?
    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header with info + sharpness controls
            HStack(spacing: 10) {
                // Score button — calibrates from the burst then scores
                Button {
                    Task { await viewModel.calibrateAndScoreCurrentCatalog() }
                } label: {
                    if viewModel.sharpnessModel.isScoring {
                        Label("Scoring…", systemImage: "scope")
                    } else if viewModel.sharpnessModel.scores.isEmpty {
                        Label("Score Sharpness", systemImage: "scope")
                    } else {
                        Label("Re-score", systemImage: "scope")
                    }
                }
                .font(.caption)
                .disabled(viewModel.sharpnessModel.isScoring || viewModel.files.isEmpty)
                .help("Auto-calibrate threshold and gain from this burst, then score sharpness")

                // Cancel button — only visible while scoring
                if viewModel.sharpnessModel.isScoring {
                    Button(role: .cancel) {
                        viewModel.sharpnessModel.cancelScoring()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle")
                    }
                    .font(.caption)
                    .tint(.red)
                    .help("Abort sharpness scoring and discard results")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }

                // Sort toggle — only visible once scores exist and not currently scoring
                if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
                    Toggle(isOn: $viewModel.sharpnessModel.sortBySharpness) {
                        Label("Sharpness", systemImage: "arrow.up.arrow.down")
                    }
                    .toggleStyle(.button)
                    .font(.caption)
                    .help("Sort thumbnails sharpest-first")
                    .onChange(of: viewModel.sharpnessModel.sortBySharpness) { _, _ in
                        Task(priority: .background) {
                            await viewModel.handleSortOrderChange()
                        }
                    }
                }

                Picker("Aperture", selection: $viewModel.sharpnessModel.apertureFilter) {
                    ForEach(ApertureFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .font(.caption)
                .frame(width: 160)
                .help("Filter by aperture — Wide for birds/portraits, Landscape for stopped-down shots")
                .onChange(of: viewModel.sharpnessModel.apertureFilter) { _, _ in
                    Task(priority: .background) {
                        await viewModel.handleSortOrderChange()
                    }
                }

                // Sharpness threshold classifier — visible once scores exist
                if !viewModel.sharpnessModel.scores.isEmpty, !viewModel.sharpnessModel.isScoring {
                    Picker("Threshold", selection: $sharpnessThreshold) {
                        ForEach([20, 30, 40, 50, 60, 70, 80], id: \.self) { pct in
                            Text("\(pct)%").tag(pct)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                    .frame(width: 70)
                    .padding(.leading, 12)
                    .help("Sharpness cut-off: images at or above this score become Keep (P), below become Rejected (X)")

                    Button("Apply") {
                        viewModel.applySharpnessThreshold(sharpnessThreshold)
                    }
                    .font(.caption)
                    .padding(.trailing, 12)
                    .help("Auto-classify all scored images using the selected sharpness threshold")
                }

                // Create a spinner when calibrating is in progress
                if viewModel.sharpnessModel.calibratingsharpnessscoring {
                    HStack {
                        ProgressView()
                        Text("Calibrating sharpness scoring, please wait...")
                    }
                }

                // Rating color filter buttons
                RatingFilterButtons(
                    activeRating: { if case let .rating(n) = ratingFilter { return n }; return nil }(),
                    onSelect: { rating in
                        let next = GridRatingFilter.rating(rating)
                        ratingFilter = ratingFilter == next ? .all : next
                    },
                    onClear: { ratingFilter = .all },
                )

                Text("P = picked, not rated")
                    .font(.caption2)
                    .foregroundStyle(Color.secondary)

                Spacer()

                // Culling progress
                let stats = cullingStats
                let ratingSum = stats.rejected + stats.kept + stats.r2 + stats.r3 + stats.r4 + stats.r5 + stats.unrated
                HStack(alignment: .top, spacing: 12) {
                    // Table 1: rejected / kept
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                        GridRow {
                            Text("✕").foregroundStyle(Color.red)
                            Text("\(stats.rejected)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("P").foregroundStyle(Color.accentColor)
                            Text("\(stats.kept)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                    }

                    // Table 2: star ratings
                    Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 2) {
                        GridRow {
                            Text("★2").foregroundStyle(Color.yellow)
                            Text("\(stats.r2)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("★3").foregroundStyle(Color.green)
                            Text("\(stats.r3)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("★4").foregroundStyle(Color.blue)
                            Text("\(stats.r4)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                        GridRow {
                            Text("★5").foregroundStyle(Color.purple)
                            Text("\(stats.r5)").foregroundStyle(Color.primary).gridColumnAlignment(.trailing)
                        }
                    }

                    // Unrated + sum
                    VStack(alignment: .leading, spacing: 2) {
                        Button {
                            ratingFilter = ratingFilter == .unrated ? .all : .unrated
                        } label: {
                            Text("\(stats.unrated) unrated")
                                .foregroundStyle(ratingFilter == .unrated ? Color.primary : Color.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Show only unrated images")
                        Text("= \(ratingSum) / \(stats.total)")
                            .foregroundStyle(ratingSum == stats.total ? Color.secondary : Color.red)
                    }
                }
                .font(.caption.monospacedDigit())
            }
            .padding()
            .background(Color.gray.opacity(0.1))

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
                .padding(.horizontal)
                .padding(.vertical, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Grid view
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: CGFloat(settings.thumbnailSizeGridView)), spacing: 12)
                        ],
                        spacing: 12,
                    ) {
                        ForEach(files, id: \.id) { file in
                            ImageItemView(
                                viewModel: viewModel,
                                file: file,
                                selectedSource: selectedSource,
                                isHovered: hoveredFileID == file.id,
                                thumbnailSize: settings.thumbnailSizeGridView,
                                onSelect: { handleToggleSelection(for: file) },
                                onDoubleSelect: { handleDoubleSelect(for: file) },
                            )
                            .id(file.id)
                            .onHover { isHovered in
                                hoveredFileID = isHovered ? file.id : nil
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
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: viewModel.sharpnessModel.isScoring)
        .animation(.easeInOut(duration: 0.15), value: ratingFilter)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showScanStats = true
                } label: {
                    Label("Statistics", systemImage: "info.circle")
                }
                .help("Show scan statistics")
                .disabled(viewModel.files.isEmpty)
            }
        }
        .sheet(isPresented: $showScanStats) {
            ScanStatsSheetView(viewModel: viewModel)
        }
        .task(id: viewModel.selectedSource) {
            await ThumbnailLoader.shared.cancelAll()
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .grid)
    }

    private func handleToggleSelection(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
    }

    private func handleDoubleSelect(for file: FileItem) {
        ZoomPreviewHandler.handle(
            file: file,
            useThumbnailAsZoomPreview: viewModel.useThumbnailAsZoomPreview,
            setNSImage: { nsImage = $0 },
            setCGImage: { cgImage = $0 },
            openWindow: { id in openWindow(id: id) },
        )
    }

    private var cullingStats: (rejected: Int, kept: Int, r2: Int, r3: Int, r4: Int, r5: Int, unrated: Int, total: Int) {
        guard let catalog = viewModel.selectedSource?.url else {
            let n = viewModel.filteredFiles.count
            return (0, 0, 0, 0, 0, 0, n, n)
        }
        var rejected = 0, kept = 0, r2 = 0, r3 = 0, r4 = 0, r5 = 0, unrated = 0
        for file in viewModel.filteredFiles {
            let hasRecord = viewModel.cullingModel.isTagged(photo: file.name, in: catalog)
            if !hasRecord {
                unrated += 1
            } else {
                switch viewModel.getRating(for: file) {
                case -1: rejected += 1
                case 0:  kept += 1
                case 2:  r2 += 1
                case 3:  r3 += 1
                case 4:  r4 += 1
                case 5:  r5 += 1
                default: unrated += 1
                }
            }
        }
        return (rejected, kept, r2, r3, r4, r5, unrated, viewModel.filteredFiles.count)
    }

    var files: [FileItem] {
        switch ratingFilter {
        case .all:
            return viewModel.filteredFiles

        case .unrated:
            guard let catalog = viewModel.selectedSource?.url else { return viewModel.filteredFiles }
            return viewModel.filteredFiles.filter { !viewModel.cullingModel.isTagged(photo: $0.name, in: catalog) }

        case .rating(0):
            return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) == 0 }

        case let .rating(n):
            return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) == n }
        }
    }
}
