import RawParserKit
import SwiftUI

enum ComparisonImageLoader {
    private static var fullSizeCache: FullSizeJPGDiskCache {
        SharedMemoryCache.shared.fullSizeJPGDiskCache
    }

    static func loadImage(for file: FileItem, useThumbnailSource: Bool = false) async -> (CGImage?, NSImage?) {
        if useThumbnailSource {
            return await loadThumbnail(for: file)
        }

        let filejpg = file.url
            .deletingPathExtension()
            .appendingPathExtension(SupportedFileType.jpg.rawValue)
        if let cgImage = OrientationNormalizedImageLoader.loadCGImage(from: filejpg) {
            return (cgImage, nil)
        }

        guard !Task.isCancelled else { return (nil, nil) }

        if let cached = await fullSizeCache.load(for: file.url) {
            return (cached, nil)
        }

        guard !Task.isCancelled else { return (nil, nil) }

        if let format = RawFormatRegistry.format(for: file.url) {
            let orientedPreview = await Task.detached(priority: .userInitiated) {
                OrientationNormalizedImageLoader.loadSonyEmbeddedPreview(from: file.url)
            }.value
            let extracted = if let orientedPreview {
                orientedPreview
            } else {
                await format.extractFullJPEG(from: file.url, fullSize: false)
            }

            guard let extracted else { return (nil, nil) }
            if let jpegData = FullSizeJPGDiskCache.jpegData(from: extracted) {
                await fullSizeCache.save(jpegData, for: file.url)
            }
            return (extracted, nil)
        }

        return (nil, nil)
    }

    private static func loadThumbnail(for file: FileItem) async -> (CGImage?, NSImage?) {
        let thumbnailSizePreview = 1616
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        let cgThumb = await RequestThumbnail.shared.requestThumbnail(
            for: file.url,
            targetSize: thumbnailSizePreview,
        )

        guard !Task.isCancelled else { return (nil, nil) }

        if settings.enableThumbnailSharpening {
            let url = file.url
            let size = CGFloat(thumbnailSizePreview)
            let amount = settings.thumbnailSharpenAmount
            let sharpened = await Task.detached(priority: .userInitiated) {
                ThumbnailSharpener.sharpenedPreview(from: url, maxDimension: size, amount: amount)
            }.value
            return (sharpened ?? cgThumb, nil)
        }

        return (cgThumb, nil)
    }
}
