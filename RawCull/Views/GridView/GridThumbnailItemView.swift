//
//  GridThumbnailItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import OSLog
import SwiftUI

struct GridThumbnailItemView: View {
    @Bindable var cullingManager: CullingModel
    @Bindable var viewModel: RawCullViewModel

    let file: FileItem
    let selectedSource: ARWSourceCatalog?
    let isHovered: Bool
    var onToggle: () -> Void = {}
    var onSelected: () -> Void = {}

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
                                width: CGFloat(savedSettings.thumbnailSizeGridView),
                                height: CGFloat(savedSettings.thumbnailSizeGridView)
                            )
                            .clipped()
                    } else if isLoading, let savedSettings {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: CGFloat(savedSettings.thumbnailSizeGridView))
                            .overlay {
                                ProgressView()
                                    .fixedSize()
                            }
                    } else if let savedSettings {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: CGFloat(savedSettings.thumbnailSizeGridView))

                            Label("No image", systemImage: "xmark")
                                .font(.caption2)
                        }
                    }
                }
                .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
                .border(Color.blue.opacity(0.5), width: isSelected ? 2 : 0)

                // File name
                Text(file.name)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
            }

            // Selection indicator and checkbox
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    // Checkbox
                    Button(action: onToggle) {
                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                            .foregroundStyle(.blue)
                            .font(.system(size: isHovered ? 18 : 16))
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .background(Color.white.opacity(0.9))
                    .clipShape(Circle())
                    .padding(4)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double click to select
            onSelected()
        }
        .onTapGesture(count: 1) {
            // Single click to toggle selection
            onToggle()
        }
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

    private var isSelected: Bool {
        guard let photoURL = selectedSource?.url else { return false }
        guard let index = cullingManager.savedFiles.firstIndex(where: { $0.catalog == photoURL }) else {
            return false
        }
        return cullingManager.savedFiles[index].filerecords?.contains { $0.fileName == file.name } ?? false
    }

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
