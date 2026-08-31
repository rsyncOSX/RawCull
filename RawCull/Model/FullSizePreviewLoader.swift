import CoreGraphics
import Foundation
import RawParserKit

nonisolated protocol FullSizePreviewLoading: Sendable {
    func loadEmbeddedPreview(for rawURL: URL) async -> CGImage?
}

nonisolated struct FullSizePreviewLoader: FullSizePreviewLoading {
    static var shared: FullSizePreviewLoader {
        FullSizePreviewLoader(
            rawLoader: RawParserKitImageLoader.shared,
            fullSizeCache: SharedMemoryCache.shared.fullSizeJPGDiskCache,
        )
    }

    private let rawLoader: any RawImageLoading
    private let fullSizeCache: FullSizeJPGDiskCache

    init(
        rawLoader: any RawImageLoading = RawParserKitImageLoader.shared,
        fullSizeCache: FullSizeJPGDiskCache,
    ) {
        self.rawLoader = rawLoader
        self.fullSizeCache = fullSizeCache
    }

    /// Keeps extraction and any fallback ImageIO JPEG recode off a UI caller's actor.
    @concurrent
    func loadEmbeddedPreview(for rawURL: URL) async -> CGImage? {
        let sidecarJPGURL = Self.sidecarJPEGURL(for: rawURL)
        let sidecarImage: CGImage? = await Task.detached(priority: .userInitiated) {
            guard FileManager.default.fileExists(atPath: sidecarJPGURL.path) else {
                return nil
            }
            return OrientationNormalizedImageLoader.loadCGImage(from: sidecarJPGURL)
        }.value

        guard !Task.isCancelled else { return nil }
        if let sidecarImage {
            return sidecarImage
        }

        if let cached = await fullSizeCache.load(for: rawURL) {
            guard !Task.isCancelled else { return nil }
            return cached
        }

        guard !Task.isCancelled else { return nil }

        let extracted = await rawLoader.previewCGImage(for: rawURL)
        guard !Task.isCancelled else { return nil }

        if let extracted {
            let sourceJPEGData = await rawLoader.embeddedPreviewJPEGData(
                for: rawURL,
                matchingPixelWidth: extracted.width,
                height: extracted.height,
            )
            guard !Task.isCancelled else { return nil }

            if let jpegData = sourceJPEGData ?? FullSizeJPGDiskCache.jpegData(from: extracted) {
                await fullSizeCache.save(jpegData, for: rawURL)
            }
        }

        return extracted
    }

    static func sidecarJPEGURL(for rawURL: URL) -> URL {
        rawURL
            .deletingPathExtension()
            .appendingPathExtension(RawImageLoadingConstants.jpegExtension)
    }
}
