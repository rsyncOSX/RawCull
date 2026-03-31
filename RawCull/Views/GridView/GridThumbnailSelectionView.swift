//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import OSLog
import SwiftUI

struct GridThumbnailSelectionView: View {
    @Environment(SettingsViewModel.self) private var settings

    @Bindable var viewModel: RawCullViewModel

    @State private var hoveredFileID: FileItem.ID?

    let selectedSource: ARWSourceCatalog?

    var body: some View {
        VStack(spacing: 0) {
            // Header with info + sharpness controls
            HStack(spacing: 10) {
                // Score button
                Button {
                    Task { await viewModel.scoreSharpnessForCurrentCatalog() }
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
                .help("Analyse sharpness for all images in this catalog")

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

                Spacer()

                Text("\(files.count) Thumbnails ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            }
        }
        .frame(minWidth: 400, minHeight: 400)
        .animation(.easeInOut(duration: 0.2), value: viewModel.sharpnessModel.isScoring)
        .task(id: viewModel.selectedSource) {
            await ThumbnailLoader.shared.cancelAll()
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
    }

    var files: [FileItem] {
        viewModel.filteredFiles
    }
}
