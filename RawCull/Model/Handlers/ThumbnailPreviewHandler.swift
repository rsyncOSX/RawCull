//
//  ThumbnailPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 14/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Type to handle Thumbnai /preview extraction and window opening
enum ThumbnailPreviewHandler {
    static func handle(
        file: FileItem,
        setNSImage: @escaping (NSImage?) -> Void,
        setCGImage _: @escaping (CGImage?) -> Void,
        openWindow _: @escaping (String) -> Void
    ) {
        Task {
            let settingsManager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsManager.thumbnailSizePreview
            let cgThumb = await SharedRequestThumbnail.shared.requestThumbnail(
                for: file.url,
                targetSize: thumbnailSizePreview
            )

            if let cgThumb {
                let nsImage = NSImage(cgImage: cgThumb, size: .zero)
                setNSImage(nsImage)
            }
        }
    }
}
