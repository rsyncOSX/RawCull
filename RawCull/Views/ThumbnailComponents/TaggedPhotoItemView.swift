//
//  TaggedPhotoItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI

struct TaggedPhotoItemView: View {
    @Environment(SettingsViewModel.self) private var settings
    @Bindable var viewModel: RawCullViewModel

    let photo: String
    let photoURL: URL? // file URL — used only for thumbnail display
    let catalogURL: URL? // catalog (directory) URL — used for model lookups
    var onSelected: () -> Void = {}

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
                        .overlay(alignment: .topTrailing) {
                            TagButtonView(
                                isTagged: isTagged,
                                isHovered: false,
                            )
                        }
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

                Text(photo)
                    .font(.caption)
                    .lineLimit(2)
            }

            if setbackground() {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .padding(5)
            }
        }
        .onTapGesture {
            onSelected()
        }
        .onDisappear {
            // Cancel loading when scrolled out of view
            if let url = photoURL {
                Logger.process.debugMessageOnly("PhotoItemView (in GRID) onAppear - RELEASE thumbnail for \(url)")
            }
        }
    }

    private var isTagged: Bool {
        if let catalogURL {
            cullingModel.isTagged(photo: photo, in: catalogURL)
        } else {
            false
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
