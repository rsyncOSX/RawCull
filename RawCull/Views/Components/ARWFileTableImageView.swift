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
    @Bindable var cullingManager: CullingModel
    @Bindable var viewModel: RawCullViewModel

    @Binding var selectedSource: ARWSourceCatalog?

    @State private var savedSettings: SavedSettings?
    @State private var file: FileItem?
    @State private var thumbnailImage: NSImage?
    @State private var isLoading: Bool = false

    let isHovered: Bool
    var onToggle: () -> Void = {}

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(viewModel.filteredFiles, id: \.id) { _ in
                    if let thumbnailImage, let savedSettings {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: CGFloat(savedSettings.thumbnailSizeGrid),
                                height: CGFloat(savedSettings.thumbnailSizeGrid)
                            )
                            .clipped()
                            .overlay(alignment: .topTrailing) { // 👈 Add overlay with alignment
                                Button(action: onToggle) {
                                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: isHovered ? 12 : 10))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Circle())
                                .padding(4)
                            }
                    }
                }
            }
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private func loadThumbnail() async {
        // Logger.process.debugMessageOnly("GridThumbnailItemView LOAD thumbnail for \(file.url)")
        isLoading = true

        let settingsManager = await SettingsViewModel.shared.asyncgetsettings()
        let thumbnailSizePreview = settingsManager.thumbnailSizePreview

        if let file {
            let cgThumb = await RequestThumbnail().requestThumbnail(
                for: file.url,
                targetSize: thumbnailSizePreview
            )

            if let cgThumb {
                let nsImage = NSImage(cgImage: cgThumb, size: .zero)
                thumbnailImage = nsImage
            } else {
                thumbnailImage = nil
            }
        }

        isLoading = false
    }

    private var isSelected: Bool {
        guard let photoURL = selectedSource?.url else { return false }
        guard let index = cullingManager.savedFiles.firstIndex(where: { $0.catalog == photoURL }) else {
            return false
        }
        return cullingManager.savedFiles[index].filerecords?.contains { $0.fileName == file?.name } ?? false
    }
}
