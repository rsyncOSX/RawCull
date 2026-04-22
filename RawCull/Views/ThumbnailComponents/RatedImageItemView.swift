//
//  RatedPhotoItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI

struct RatedImageItemView: View {
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Bindable var viewModel: RawCullViewModel

    let photo: String
    let photoURL: URL? // file URL — used only for thumbnail display
    let catalogURL: URL? // catalog (directory) URL — used for model lookups
    var isSelected: Bool = false
    var isMultiSelected: Bool = false
    var onSelected: () -> Void = {}
    var onDoubleSelected: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading) {
                ZStack {
                    if let photoURL {
                        ThumbnailImageView(
                            url: photoURL,
                            targetSize: settings.thumbnailSizeGrid,
                            style: .list,
                        )
                        .frame(
                            width: CGFloat(settings.thumbnailSizeGrid),
                            height: CGFloat(settings.thumbnailSizeGrid),
                        )
                        .clipped()
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: CGFloat(settings.thumbnailSizeGrid))

                            Label("No image available", systemImage: "xmark")
                        }
                    }
                }
                .background(setbackground() ? Color.blue.opacity(0.2) : Color.clear)
                .overlay(alignment: .topTrailing) {
                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white, Color.teal)
                            .padding(5)
                            .shadow(radius: 2)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0),
                )
                .shadow(
                    color: isSelected ? Color.accentColor.opacity(0.65) : .clear,
                    radius: isSelected ? 8 : 0,
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(photo)
                    .font(.caption)
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

                // Rating color strip — 1=red 2=yellow 3=green 4=blue 5=purple
                if let color = ratingColor {
                    color.frame(height: 4)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(borderColor, lineWidth: borderWidth),
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.75) : .clear,
            radius: isSelected ? 12 : 0,
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleSelected() }
        .onTapGesture(count: 1) { onSelected() }
        .onDisappear {
            // Cancel loading when scrolled out of view
            if let url = photoURL {
                Logger.process.debugMessageOnly("PhotoItemView (in GRID) onAppear - RELEASE thumbnail for \(url)")
            }
        }
    }

    private var borderColor: Color {
        if isSelected { return Color.accentColor }
        if isMultiSelected { return Color.teal }
        return Color(white: 0.18)
    }

    private var borderWidth: CGFloat {
        if isSelected { return 2.5 }
        if isMultiSelected { return 2.0 }
        return 1
    }

    private var ratingColor: Color? {
        guard let catalogURL,
              let entry = cullingModel.savedFiles.first(where: { $0.catalog == catalogURL }),
              let record = entry.filerecords?.first(where: { $0.fileName == photo })
        else { return nil }
        switch record.rating ?? 0 {
        case -1: return .red
        case 2: return .yellow
        case 3: return .green
        case 4: return .blue
        case 5: return .purple
        default: return nil
        }
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    func setbackground() -> Bool {
        guard let catalogURL else { return false }
        // Find the saved file entry matching this catalog directory URL
        guard let entry = cullingModel.savedFiles.first(where: { $0.catalog == catalogURL }) else {
            return false
        }
        // Check if any filerecord has a matching fileName
        if let records = entry.filerecords {
            return records.contains { $0.fileName == photo }
        }
        return false
    }
}
