//
//  RatedImageItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import SwiftUI

struct RatedImageItemView: View {
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    @Bindable var viewModel: RawCullViewModel

    let file: FileItem
    let catalogURL: URL? // catalog (directory) URL — used for model lookups
    var isSelected: Bool = false
    var isMultiSelected: Bool = false
    var onSelected: () -> Void = {}
    var onDoubleSelected: () -> Void = {}

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading) {
                ZStack {
                    ThumbnailImageView(
                        file: file,
                        targetSize: gridCacheTargetSize,
                        style: .grid,
                    )
                    .frame(
                        width: CGFloat(settings.thumbnailSizeGrid),
                        height: CGFloat(settings.thumbnailSizeGrid),
                    )
                    .clipped()
                }
                .background(setbackground() ? Color.blue.opacity(0.2) : Color.clear)
                .overlay(alignment: .topTrailing) {
                    if isMultiSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white, Color.teal)
                            .padding(5)
                    }
                }
                .overlay(alignment: .topLeading) {
                    CurrentRatingBadgeView(
                        rating: ratingDisplay,
                        density: .compact,
                    )
                    .padding(5)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0),
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))

                Text(file.name)
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
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected || isMultiSelected ? borderColor.opacity(isSelected ? 0.14 : 0.1) : Color.clear),
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleSelected() }
        .onTapGesture(count: 1) { onSelected() }
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
        guard let rating = ratingValue else { return nil }
        switch rating {
        case -1: return .red
        case 2: return .yellow
        case 3: return .green
        case 4: return .blue
        case 5: return .purple
        default: return nil
        }
    }

    private var ratingDisplay: RatingDisplay {
        RatingDisplay(rating: ratingValue ?? 0, isExplicit: ratingValue != nil)
    }

    private var ratingValue: Int? {
        guard let catalogURL,
              let entry = cullingModel.savedFiles.first(where: { $0.catalog == catalogURL }),
              let record = entry.filerecords?.first(where: { $0.fileName == file.name })
        else { return nil }
        return record.rating
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
            return records.contains { $0.fileName == file.name }
        }
        return false
    }

    private var gridCacheTargetSize: Int {
        min(settings.thumbnailSizeGrid, 200)
    }
}
