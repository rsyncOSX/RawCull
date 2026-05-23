import ImageIO
import SwiftUI

enum ComparisonImageLoader {
    private static var fullSizeCache: FullSizeJPGDiskCache {
        SharedMemoryCache.shared.fullSizeJPGDiskCache
    }

    static func loadImage(for file: FileItem) async -> (CGImage?, NSImage?) {
        let filejpg = file.url
            .deletingPathExtension()
            .appendingPathExtension(SupportedFileType.jpg.rawValue)
        if let cgImage = loadCGImage(from: filejpg) {
            return (cgImage, nil)
        }

        guard !Task.isCancelled else { return (nil, nil) }

        if let cached = await fullSizeCache.load(for: file.url) {
            return (cached, nil)
        }

        guard !Task.isCancelled else { return (nil, nil) }

        if let format = RawFormatRegistry.format(for: file.url),
           let extracted = await format.extractFullJPEG(from: file.url, fullSize: false) {
            if let jpegData = FullSizeJPGDiskCache.jpegData(from: extracted) {
                await fullSizeCache.save(jpegData, for: file.url)
            }
            return (extracted, nil)
        }

        return (nil, nil)
    }

    private static func loadCGImage(from url: URL) -> CGImage? {
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
