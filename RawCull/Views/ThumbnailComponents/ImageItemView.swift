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

    let file: FileItem
    let selectedSource: ARWSourceCatalog?
    let isHovered: Bool
    let thumbnailSize: Int

    var onToggle: () -> Void = {}
    var onSelected: () -> Void = {}

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var shimmerOffset: CGFloat = -1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                if let thumbnailImage {
                    Image(nsImage: thumbnailImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
                        .clipped()
                        .overlay(alignment: .topTrailing) {
                            TagButtonView(isTagged: isTagged, isHovered: isHovered, onToggle: onToggle)
                        }
                        // Green tint ribbon at bottom when tagged
                        .overlay(alignment: .bottom) {
                            if isTagged {
                                Rectangle()
                                    .fill(Color.green.opacity(0.55))
                                    .frame(height: 3)
                            }
                        }
                } else if isLoading {
                    shimmerPlaceholder
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.system(size: 20, weight: .thin))
                                .foregroundStyle(Color(white: 0.4))
                            Text("No image")
                                .font(.system(size: 9, weight: .light))
                                .foregroundStyle(Color(white: 0.35))
                        }
                    }
                }
            }
            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
            // Selected: accent glow border
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0),
            )
            .shadow(
                color: isSelected ? Color.accentColor.opacity(0.5) : .clear,
                radius: isSelected ? 6 : 0,
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))

            // Filename strip
            Text(file.name)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? Color.accentColor : Color(white: 0.6))
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.1))
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(white: isHovered ? 0.35 : 0.18), lineWidth: 1),
        )
        .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onSelected() }
        .onTapGesture(count: 1) { onToggle() }
        .task(id: file.url) {
            guard thumbnailImage == nil else { return }
            isLoading = true
            thumbnailImage = await ThumbnailLoader.shared.thumbnailLoader(file: file)
            isLoading = false
        }
        .onDisappear {
            thumbnailImage = nil
            isLoading = false
        }
    }

    // MARK: - Subviews

    private var shimmerPlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
            .overlay(
                GeometryReader { geo in
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color(white: 0.3).opacity(0.4),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing,
                            ),
                        )
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: shimmerOffset * geo.size.width)
                }
                .clipped(),
            )
            .onAppear {
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    shimmerOffset = 1.5
                }
            }
    }

    // MARK: - Helpers

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    private var isTagged: Bool {
        guard let photoURL = selectedSource?.url else { return false }
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == photoURL }) else {
            return false
        }
        return cullingModel.savedFiles[index].filerecords?.contains { $0.fileName == file.name } ?? false
    }

    private var isSelected: Bool {
        viewModel.selectedFile?.id == file.id
    }
}

struct TagButtonView: View {
    let isTagged: Bool
    let isHovered: Bool
    var onToggle: () -> Void

    var body: some View {
        Image(systemName: isTagged ? "checkmark.circle.fill" : "circle")
            .font(.system(size: isHovered ? 14 : 10))
            .foregroundStyle(isTagged ? Color.green : Color.white.opacity(0.8))
            .shadow(color: .black.opacity(0.5), radius: 2)
            .padding(5)
            .background(.ultraThinMaterial)
            .clipShape(Circle())
    }
}
