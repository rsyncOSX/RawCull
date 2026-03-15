//
//  TaggedPhotoItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI

struct TaggedPhotoItemView: View {
    @Bindable var viewModel: RawCullViewModel

    let photo: String
    let photoURL: URL?
    var onSelected: () -> Void = {}

    @State private var savedSettings: SavedSettings?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading) {
                ZStack {
                    if let savedSettings, let photoURL {
                        ThumbnailImageView(
                            url: photoURL,
                            targetSize: savedSettings.thumbnailSizeGrid,
                            style: .list
                        )
                            .frame(
                                width: CGFloat(savedSettings.thumbnailSizeGrid),
                                height: CGFloat(savedSettings.thumbnailSizeGrid),
                            )
                            .clipped()
                            .overlay(alignment: .topTrailing) {
                                TagButtonView(isTagged: isTagged, isHovered: false, onToggle: {})
                            }
                    } else if let savedSettings {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: CGFloat(savedSettings.thumbnailSizeGrid))

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
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    private var isTagged: Bool {
        if let photoURL {
            cullingModel.isTagged(photo: photo, in: photoURL)
        } else {
            false
        }
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    func setbackground() -> Bool {
        guard let photoURL else { return false }
        // Find the saved file entry matching this photoURL
        guard let entry = cullingModel.savedFiles.first(where: { $0.catalog == photoURL }) else {
            return false
        }
        // Check if any filerecord has a matching fileName
        if let records = entry.filerecords {
            return records.contains { $0.fileName == photo }
        }
        return false
    }
}
