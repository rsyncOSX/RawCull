//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import AppKit
import OSLog
import SwiftUI

struct GridThumbnailSelectionView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Environment(\.openWindow) private var openWindow

    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?
    @State private var ratingFilter: Int?
    @State private var sharpnessThreshold: Int = 50

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
                    activeRating: ratingFilter,
                    onSelect: { rating in ratingFilter = ratingFilter == rating ? nil : rating },
                    onClear: { ratingFilter = nil },
                )

                Spacer()

                // Culling progress
                let stats = cullingStats
                HStack(spacing: 8) {
                    Text("✕ \(stats.rejected)").foregroundStyle(.red)
                    Text("P \(stats.kept)").foregroundStyle(Color.accentColor)
                    Text("\(stats.unrated) unrated").foregroundStyle(.secondary)
                    Text("/ \(stats.total)").foregroundStyle(.secondary)
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
                                onTag: {
                                    Task { await viewModel.toggleTag(for: file) }
                                },
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

    private var cullingStats: (rejected: Int, kept: Int, unrated: Int, total: Int) {
        guard let catalog = viewModel.selectedSource?.url else {
            return (0, 0, viewModel.filteredFiles.count, viewModel.filteredFiles.count)
        }
        var rejected = 0, kept = 0, unrated = 0
        for file in viewModel.filteredFiles {
            let hasRecord = viewModel.cullingModel.isTagged(photo: file.name, in: catalog)
            if !hasRecord {
                unrated += 1
            } else {
                let r = viewModel.getRating(for: file)
                if r == -1 { rejected += 1 } else { kept += 1 }
            }
        }
        return (rejected, kept, unrated, viewModel.filteredFiles.count)
    }

    var files: [FileItem] {
        guard let ratingFilter else { return viewModel.filteredFiles }
        if ratingFilter == 0 {
            // Keepers mode: show keep (0) and rated images (2–5), exclude rejected (–1)
            return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) >= 0 }
        }
        return viewModel.filteredFiles.filter { viewModel.getRating(for: $0) == ratingFilter }
    }
}
