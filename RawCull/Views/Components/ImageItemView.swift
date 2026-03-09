//
//  ImageItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 09/03/2026.
//


import OSLog
import SwiftUI

struct ImageItemView: View {
    @Bindable var viewModel: RawCullViewModel
    @Bindable var cullingModel: CullingModel

    let file: FileItem
    let selectedSource: ARWSourceCatalog?
    let isHovered: Bool
    let gridview: Bool

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
                    if let thumbnailImage {
                        Image(nsImage: thumbnailImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(
                                width: CGFloat(framewidtheight()),
                                height: CGFloat(framewidtheight())
                            )
                            .clipped()
                            .overlay(alignment: .topTrailing) { // 👈 Add overlay with alignment
                                Button(action: onToggle) {
                                    Image(systemName: isTagged ? "checkmark.square.fill" : "square")
                                        .foregroundStyle(.blue)
                                        .font(.system(size: isHovered ? 12 : 10))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                                .background(Color.white.opacity(0.9))
                                .clipShape(Circle())
                                .padding(4)
                            }
                    } else if isLoading {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(height: CGFloat(framewidtheight()))
                            .overlay {
                                ProgressView()
                                    .fixedSize()
                            }
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: CGFloat(framewidtheight()))

                            Label("No image", systemImage: "xmark")
                                .font(.caption2)
                        }
                    }
                }
                .background(isTagged ? Color.blue.opacity(0.2) : Color.clear)
                .border(Color.red.opacity(0.5), width: isSelected ? 2 : 0)

                // File name
                Text(file.name)
                    .font(.caption)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
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
            thumbnailImage = await LoadThumbnail().loadThumbnail(file: file)
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
        .onDisappear {
            // Clear when scrolled out of view to free memory
            Logger.process.debugMessageOnly("ImageItemView RELEASE thumbnail for \(file.url)")
            isLoading = false
            thumbnailImage = nil
        }
    }

    // MARK: - Helper Methods

    private var isTagged: Bool {
        guard let photoURL = selectedSource?.url else { return false }
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == photoURL }) else {
            return false
        }
        return cullingModel.savedFiles[index].filerecords?.contains { $0.fileName == file.name } ?? false
    }

    private var isSelected: Bool {
        let selectedID = viewModel.selectedFile?.id
        return selectedID == file.id
    }

    /// Set frame heigth and width
    private func framewidtheight() -> Int {
        if let savedSettings {
            if gridview {
                return savedSettings.thumbnailSizeGridView
            } else {
                return savedSettings.thumbnailSizeGrid
            }
        }
        return 100
    }
}
