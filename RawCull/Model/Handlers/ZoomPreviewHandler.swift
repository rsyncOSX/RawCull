//
//  ZoomPreviewHandler.swift
//  RawCull
//
//  Created by Thomas Evensen on 08/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Type to handle JPG/preview extraction and window opening
enum ZoomPreviewHandler {
    @discardableResult
    static func handleOverlay(
        file: FileItem,
        useThumbnailAsZoomPreview: Bool = false,
        thumbnailSizePreview: Int = 1616,
        viewModel: RawCullViewModel,
    ) -> Task<Void, Never> {
        if useThumbnailAsZoomPreview {
            return Task {
                await MainActor.run {
                    viewModel.zoomOverlayCGImage = nil
                    viewModel.zoomOverlayNSImage = nil
                }

                let cgThumb = await RequestThumbnail.shared.requestThumbnail(
                    for: file.url,
                    targetSize: thumbnailSizePreview,
                )

                guard !Task.isCancelled else { return }

                await MainActor.run {
                    if let cgThumb {
                        viewModel.zoomOverlayNSImage = NSImage(cgImage: cgThumb, size: .zero)
                    }
                    viewModel.zoomOverlayVisible = true
                }
            }
        } else {
            let filejpg = file.url.deletingPathExtension().appendingPathExtension(SupportedFileType.jpg.rawValue)
            if let cgImage = loadCGImage(from: filejpg) {
                viewModel.zoomOverlayCGImage = nil
                viewModel.zoomOverlayNSImage = nil
                viewModel.zoomOverlayCGImage = cgImage
                viewModel.zoomOverlayVisible = true
                return Task {}
            } else {
                return Task {
                    await MainActor.run {
                        viewModel.zoomOverlayNSImage = nil
                        viewModel.zoomOverlayCGImage = nil
                        viewModel.zoomOverlayVisible = true
                    }

                    guard !Task.isCancelled else { return }

                    if file.url.pathExtension.lowercased() == SupportedFileType.arw.rawValue {
                        let extracted = await JPGSonyARWExtractor.jpgSonyARWExtractor(from: file.url)

                        guard !Task.isCancelled else { return }

                        if let extracted {
                            await MainActor.run {
                                viewModel.zoomOverlayCGImage = extracted
                            }
                        }
                    }
                }
            }
        }
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
        // Disable source-level AND decode-level ImageIO caching. Without this, ImageIO
        // retains the decoded pixel buffer (~188 MB for a 50 MP JPEG) in a process-level
        // cache that is NOT subject to ARC — setting cgImage = nil in onDisappear does not
        // free it. CGImageSourceRemoveCacheAtIndex acts as a belt-and-suspenders eviction
        // before imageSource goes out of scope.
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, decodeOptions) else {
            return nil
        }
        CGImageSourceRemoveCacheAtIndex(imageSource, 0)
        return cgImage
    }
}
