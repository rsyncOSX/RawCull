//
//  ARWFileTableItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

//
//  GridThumbnailItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import OSLog
import SwiftUI

struct ARWFileTableItemView: View {
    @Bindable var cullingManager: CullingModel
    @Bindable var viewModel: RawCullViewModel

    let file: FileItem
    let selectedSource: ARWSourceCatalog?

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var savedSettings: SavedSettings?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail
                ZStack {
                    if let thumbnailImage, let savedSettings {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: CGFloat(savedSettings.thumbnailSizeGrid),
                                height: CGFloat(savedSettings.thumbnailSizeGrid)
                            )
                            .clipped()
                    } else if isLoading, let savedSettings {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: CGFloat(savedSettings.thumbnailSizeGrid))
                            .overlay {
                                ProgressView()
                                    .fixedSize()
                            }
                    } else if let savedSettings {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: CGFloat(savedSettings.thumbnailSizeGrid))

                            Label("No image", systemImage: "xmark")
                                .font(.caption2)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .task(id: file.url) {
            await loadThumbnail()
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
        .onDisappear {
            // Clear when scrolled out of view to free memory
            Logger.process.debugMessageOnly("GridThumbnailItemView RELEASE thumbnail for \(file.url)")
            isLoading = false
            thumbnailImage = nil
        }
    }

    // MARK: - Helper Methods

    private func loadThumbnail() async {
        Logger.process.debugMessageOnly("GridThumbnailItemView LOAD thumbnail for \(file.url)")
        isLoading = true

        let settingsManager = await SettingsViewModel.shared.asyncgetsettings()
        let thumbnailSizePreview = settingsManager.thumbnailSizePreview

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

        isLoading = false
    }
}
