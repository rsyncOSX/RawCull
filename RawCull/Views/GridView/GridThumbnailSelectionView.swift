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
    @Bindable var cullingManager: CullingModel

    @State private var savedSettings: SavedSettings?
    @State private var hoveredFileID: FileItem.ID?

    let files: [FileItem]
    let selectedSource: ARWSourceCatalog?

    var body: some View {
        VStack(spacing: 0) {
            // Header with info
            HStack {
                Text("Thumbnail Grid")
                    .font(.headline)

                Spacer()

                Text("\(files.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))

            // Grid view
            ScrollView {
                if let savedSettings {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: CGFloat(savedSettings.thumbnailSizeGridView)), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(files, id: \.id) { file in
                            GridThumbnailItemView(
                                cullingManager: cullingManager,
                                viewModel: viewModel,
                                file: file,
                                selectedSource: selectedSource,
                                isHovered: hoveredFileID == file.id,
                                onToggle: { handleToggleSelection(for: file) },
                                onSelected: {
                                    viewModel.selectedFileID = file.id
                                    viewModel.selectedFile = file
                                }
                            )
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
    }

    private func handleToggleSelection(for file: FileItem) {
        cullingManager.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name
        )
    }
}
