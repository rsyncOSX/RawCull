//
//  PhotoItemView.swift
//  RawCull
//
//  Created by Thomas Evensen on 21/01/2026.
//

import OSLog
import SwiftUI

struct PhotoItemView: View {
    let photo: String
    let photoURL: URL?
    var onSelected: () -> Void = {}

    @Bindable var cullingmanager: CullingModel

    @State private var thumbnailImage: NSImage?
    @State private var isLoading = false
    @State private var savedSettings: SavedSettings?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading) {
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
        .onAppear {
            guard let url = photoURL else { return }
            Logger.process.debugMessageOnly("PhotoItemView (in GRID) onAppear - LOAD thumbnail for \(url)")
            isLoading = true
            Task {
                // Most likely a thumbnail is received from the populated NSCache<NSURL, NSImage>().
                // Use preview size to match preload cache to avoid disk reads
                let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
                let thumbnailSizePreview = settingsmanager.thumbnailSizePreview
                let cgThumb = await RequestThumbnail().requestThumbnail(
                    for: url,
                    targetSize: thumbnailSizePreview
                )
                if let cgThumb {
                    // Create an NSImage from the CGImage. Use scale 1.0 and .up orientation by default.
                    let nsImage = NSImage(cgImage: cgThumb, size: .zero)
                    thumbnailImage = nsImage
                } else {
                    thumbnailImage = nil
                }
                isLoading = false
            }
        }
        .onDisappear {
            // Cancel loading when scrolled out of view
            if let url = photoURL {
                Logger.process.debugMessageOnly("PhotoItemView (in GRID) onAppear - RELEASE thumbnail for \(url)")
            }
            isLoading = false
            thumbnailImage = nil
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    func setbackground() -> Bool {
        guard let photoURL else { return false }
        // Find the saved file entry matching this photoURL
        guard let entry = cullingmanager.savedFiles.first(where: { $0.catalog == photoURL }) else {
            return false
        }
        // Check if any filerecord has a matching fileName
        if let records = entry.filerecords {
            return records.contains { $0.fileName == photo }
        }
        return false
    }
}
