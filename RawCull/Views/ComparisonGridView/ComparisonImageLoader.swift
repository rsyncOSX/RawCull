import RawParserKit
import SwiftUI

struct ComparisonDecodedImage {
    let displayCGImage: CGImage?
    let analysisCGImage: CGImage?
    let nsImage: NSImage?
}

enum ComparisonImageLoader {
    static func loadImage(for file: FileItem, useThumbnailSource: Bool = false) async -> ComparisonDecodedImage {
        if useThumbnailSource {
            return await loadThumbnail(for: file)
        }

        let image = await FullSizePreviewLoader.shared.loadEmbeddedPreview(for: file.url)
        return ComparisonDecodedImage(
            displayCGImage: image,
            analysisCGImage: image,
            nsImage: nil,
        )
    }

    private static func loadThumbnail(for file: FileItem) async -> ComparisonDecodedImage {
        let thumbnailSizePreview = 1616
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        let cgThumb = await RequestThumbnail.shared.requestThumbnail(
            for: file.url,
            targetSize: thumbnailSizePreview,
            purpose: .preview,
        )

        guard !Task.isCancelled else { return emptyImage }

        if settings.enableThumbnailSharpening {
            let url = file.url
            let size = CGFloat(thumbnailSizePreview)
            let amount = settings.thumbnailSharpenAmount
            let sharpened = await Task(priority: .userInitiated) { @concurrent () -> CGImage? in
                guard !Task.isCancelled else { return nil }
                guard let image = ThumbnailSharpener.sharpenedPreview(from: url, maxDimension: size, amount: amount) else {
                    return nil
                }
                guard !Task.isCancelled else { return nil }
                return OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: url)
            }.value
            guard !Task.isCancelled else { return emptyImage }
            return thumbnailImages(
                unsharpened: cgThumb,
                sharpened: sharpened,
                sharpeningEnabled: true,
            )
        }

        return thumbnailImages(
            unsharpened: cgThumb,
            sharpened: nil,
            sharpeningEnabled: false,
        )
    }

    static func thumbnailImages(
        unsharpened: CGImage?,
        sharpened: CGImage?,
        sharpeningEnabled: Bool,
    ) -> ComparisonDecodedImage {
        ComparisonDecodedImage(
            displayCGImage: sharpeningEnabled ? sharpened ?? unsharpened : unsharpened,
            analysisCGImage: unsharpened,
            nsImage: nil,
        )
    }

    private static var emptyImage: ComparisonDecodedImage {
        ComparisonDecodedImage(displayCGImage: nil, analysisCGImage: nil, nsImage: nil)
    }
}
