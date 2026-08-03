import RawParserKit
import SwiftUI

enum ComparisonImageLoader {
    static func loadImage(for file: FileItem, useThumbnailSource: Bool = false) async -> (CGImage?, NSImage?) {
        if useThumbnailSource {
            return await loadThumbnail(for: file)
        }

        return await (FullSizePreviewLoader.shared.loadEmbeddedPreview(for: file.url), nil)
    }

    private static func loadThumbnail(for file: FileItem) async -> (CGImage?, NSImage?) {
        let thumbnailSizePreview = 1616
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        let cgThumb = await RequestThumbnail.shared.requestThumbnail(
            for: file,
            targetSize: thumbnailSizePreview,
            purpose: .preview,
        )

        guard !Task.isCancelled else { return (nil, nil) }

        if settings.enableThumbnailSharpening {
            let url = file.url
            let size = CGFloat(thumbnailSizePreview)
            let amount = settings.thumbnailSharpenAmount
            let sharpened = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let image = ThumbnailSharpener.sharpenedPreview(from: url, maxDimension: size, amount: amount) else {
                    return nil
                }
                return OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: url)
            }.value
            return (sharpened ?? cgThumb, nil)
        }

        return (cgThumb, nil)
    }
}
