//
//  ARWFileTableImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

import SwiftUI

/*
 isHovered: hoveredFileID == file.id,
 onToggle: { handleToggleSelection(for: file) },
 onSelected: {
     viewModel.selectedFileID = file.id
     viewModel.selectedFile = file
 }
 */

struct ARWFileTableImageView: View {
    @Bindable var viewModel: RawCullViewModel
    @Bindable var cullingManager: CullingModel

    @State private var savedSettings: SavedSettings?
    @State private var hoveredFileID: FileItem.ID?

    let files: [FileItem]
    let selectedSource: ARWSourceCatalog?

    var body: some View {
        VStack(spacing: 0) {
            // Grid view
            ScrollView(.vertical) {
                if let savedSettings {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: CGFloat(savedSettings.thumbnailSizeGrid)), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(files, id: \.id) { file in
                            ARWFileTableItemView(
                                cullingManager: cullingManager,
                                viewModel: viewModel,
                                file: file,
                                selectedSource: selectedSource
                            )
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(height: 100)
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await cullingManager.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name
            )
        }
    }
}
