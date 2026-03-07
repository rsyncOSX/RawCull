//
//  LoadThumbnail.swift
//  RawCull
//
//  Created by Thomas Evensen on 07/03/2026.
//

import OSLog
import Foundation
import AppKit

actor LoadThumbnail {
    @concurrent nonisolated
    func loadThumbnail(file: FileItem) async -> NSImage? {
        Logger.process.debugThreadOnly("LoadThumbnail LOAD thumbnail for \(file.url)")
        
        let settingsManager = await SettingsViewModel.shared.asyncgetsettings()
        let thumbnailSizePreview = settingsManager.thumbnailSizePreview

        let cgThumb = await RequestThumbnail().requestThumbnail(
            for: file.url,
            targetSize: thumbnailSizePreview
        )

        if let cgThumb {
            let nsImage = NSImage(cgImage: cgThumb, size: .zero)
            return nsImage
        } else {
            return nil
        }
    }
}
