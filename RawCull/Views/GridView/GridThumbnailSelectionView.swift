//
//  GridThumbnailSelectionView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import OSLog
import SwiftUI

struct GridThumbnailSelectionView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var savedSettings: SavedSettings?
    @State private var hoveredFileID: FileItem.ID?

    let selectedSource: ARWSourceCatalog?

    var body: some View {
        VStack(spacing: 0) {
            // Header with info
            HStack {
                Spacer()

                Text("\(files.count) Thumbnails ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            // Grid view
            // ScrollView(.horizontal)
            ScrollView {
                if let savedSettings {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: CGFloat(savedSettings.thumbnailSizeGridView)), spacing: 12)
                        ],
                        spacing: 12,
                    ) {
                        ForEach(files, id: \.id) { file in
                            ImageItemView(
                                viewModel: viewModel,
                                file: file,
                                selectedSource: selectedSource,
                                isHovered: hoveredFileID == file.id,
                                thumbnailSize: savedSettings.thumbnailSizeGridView,
                                // One click for select only
                                onToggle: { handleToggleSelection(for: file) },
                                // Double clik for tag Image
                                onSelected: {
                                    Task {
                                        await cullingModel.toggleSelectionSavedFiles(
                                            in: file.url,
                                            toggledfilename: file.name,
                                        )
                                    }
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
        }
        .frame(minWidth: 400, minHeight: 400)
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
        .task(id: viewModel.selectedSource) {
            await ThumbnailLoader.shared.cancelAll()
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    var files: [FileItem] {
        viewModel.files
    }
}
