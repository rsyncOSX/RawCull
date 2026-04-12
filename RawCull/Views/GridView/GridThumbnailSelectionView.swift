//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import AppKit
import OSLog
import SwiftUI

enum GridRatingFilter: Equatable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}

private enum ActiveSheet: String, Identifiable {
    case stats, scoringParams
    var id: String {
        rawValue
    }
}

struct GridThumbnailSelectionView: View {
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Environment(\.openWindow) private var openWindow

    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: GridRatingFilter = .all
    @State private var sharpnessThreshold: Int = 50
    @State private var activeSheet: ActiveSheet?

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header with info + sharpness controls
            HStack(spacing: 10) {
                SharpnessControlsView(viewModel: viewModel, sharpnessThreshold: $sharpnessThreshold)

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

                CullingStatsView(stats: cullingStats, ratingFilter: $ratingFilter)
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
                                isHovered: hoveredFileID == file.id,
                                isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
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
        .toolbar { gridToolbar }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .stats:
                ScanStatsSheetView(viewModel: viewModel)

            case .scoringParams:
                ScoringParametersSheetView(
                    config: Bindable(viewModel.sharpnessModel.focusMaskModel).config,
                    thumbnailMaxPixelSize: Bindable(viewModel.sharpnessModel).thumbnailMaxPixelSize,
                )
            }
        }
        .task(id: viewModel.selectedSource) {
            viewModel.selectedFileIDs = []
            await ThumbnailLoader.shared.cancelAll()
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
            viewModel.selectedFile = file
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
            viewModel.selectedFile = file
        }
    }

    private func handleDoubleSelect(for file: FileItem) {
        viewModel.selectedFile = file
        viewModel.selectedFileID = file.id
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
                case 0: kept += 1
                case 2: r2 += 1
                case 3: r3 += 1
                case 4: r4 += 1
                case 5: r5 += 1
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

// MARK: - Toolbar

extension GridThumbnailSelectionView {
    @ToolbarContentBuilder
    var gridToolbar: some ToolbarContent {
        if viewModel.selectedFileIDs.count > 1 {
            ToolbarItem(placement: .primaryAction) {
                Text("\(viewModel.selectedFileIDs.count) selected — press a rating key to apply")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { settings.showScoringBadge },
                set: { settings.showScoringBadge = $0; Task { await settings.saveSettings() } },
            )) {
                Label("Score Badge", systemImage: "number.circle")
            }
            .toggleStyle(.button)
            .help("Show sharpness score badge on thumbnails (disable for smoother scrolling)")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: Binding(
                get: { settings.showSaliencyBadge },
                set: { settings.showSaliencyBadge = $0; Task { await settings.saveSettings() } },
            )) {
                Label("Saliency Badge", systemImage: "eye.circle")
            }
            .toggleStyle(.button)
            .help("Show saliency badge on thumbnails")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                activeSheet = .scoringParams
            } label: {
                Label("Scoring Parameters", systemImage: "slider.horizontal.3")
            }
            .help("Configure sharpness scoring parameters")
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                activeSheet = .stats
            } label: {
                Label("Statistics", systemImage: "info.circle")
            }
            .help("Show scan statistics")
            .disabled(viewModel.files.isEmpty)
        }
    }
}
