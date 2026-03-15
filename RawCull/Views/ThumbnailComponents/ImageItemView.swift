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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail area
            ZStack {
                ThumbnailImageView(
                    file: file,
                    targetSize: thumbnailSize,
                    style: .grid,
                    showsShimmer: true
                )
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
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    private var isTagged: Bool {
        if let photoURL = selectedSource?.url {
            cullingModel.isTagged(photo: file.name, in: photoURL)
        } else {
            false
        }
    }
    
    private var isSelected: Bool {
        viewModel.selectedFile?.id == file.id
    }
}
