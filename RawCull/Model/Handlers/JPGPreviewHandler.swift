//
//  JPGPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Type to handle JPG/preview extraction and window opening
enum JPGPreviewHandler {
    static func handle(
        file: FileItem,
        useThumbnailAsZoomPreview: Bool = false,
        thumbnailSizePreview: Int = 2048,
        setNSImage: @escaping (NSImage?) -> Void,
        setCGImage: @escaping (CGImage?) -> Void,
        openWindow: @escaping (String) -> Void
    ) {
        if useThumbnailAsZoomPreview {
            Task {
                let cgThumb = await SharedRequestThumbnail.shared.requestthumbnail(
                    for: file.url,
                    targetSize: thumbnailSizePreview
                )

                if let cgThumb {
                    let nsImage = NSImage(cgImage: cgThumb, size: .zero)
                    setNSImage(nsImage)
                }
                openWindow(WindowIdentifier.zoomnsImage.rawValue)
            }
        } else {
            let filejpg = file.url.deletingPathExtension().appendingPathExtension(SupportedFileType.jpg.rawValue)
            if let image = NSImage(contentsOf: filejpg) {
                setNSImage(image)
                // The jpgs are already created, open view shows the photo immidiate
                openWindow(WindowIdentifier.zoomnsImage.rawValue)
            } else {
                Task {
                    setCGImage(nil)
                    // Open the view here to indicate process of extracting the cgImage
                    openWindow(WindowIdentifier.zoomcgImage.rawValue)
                    // let extractor = ExtractEmbeddedPreview()
                    if file.url.pathExtension.lowercased() == SupportedFileType.arw.rawValue {
                        if let mycgImage = await enumPreviewExtractor.extractEmbeddedPreview(
                            from: file.url
                        ) {
                            setCGImage(mycgImage)
                        }
                    }
                }
            }
        }
    }
}
