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

    /// Keeps extraction and the synchronous ImageIO JPEG recode off a UI caller's actor.
    @concurrent
    func loadEmbeddedPreview(for rawURL: URL) async -> CGImage? {
        let sidecarJPGURL = Self.sidecarJPEGURL(for: rawURL)
        let sidecarImage = await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadCGImage(from: sidecarJPGURL)
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

        if let extracted,
           let jpegData = FullSizeJPGDiskCache.jpegData(from: extracted) {
            await fullSizeCache.save(jpegData, for: rawURL)
        }

        return extracted
    }

    static func sidecarJPEGURL(for rawURL: URL) -> URL {
        rawURL
            .deletingPathExtension()
            .appendingPathExtension(RawImageLoadingConstants.jpegExtension)
    }
}
