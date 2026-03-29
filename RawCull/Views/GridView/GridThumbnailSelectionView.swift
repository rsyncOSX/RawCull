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

    /// @State private var savedSettings: SavedSettings?
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

                // Sort toggle — only visible once scores exist
                if !viewModel.sharpnessModel.scores.isEmpty {
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

            // Grid view
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
                            // One click for select only
                            onToggle: { handleToggleSelection(for: file) },
                            // Double clik for tag Image
                            onSelected: {
                                /*
                                 Task {
                                     viewModel.selectFile(file)
                                     Task {
                                         await viewModel.toggleTag(for: file)
                                     }
                                 }
                                  */
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
        }
        .frame(minWidth: 400, minHeight: 400)
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
