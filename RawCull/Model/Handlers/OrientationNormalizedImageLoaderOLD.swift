import Foundation
import ImageIO
import RawParserKit

enum OrientationNormalizedImageLoader {
    nonisolated static func loadCGImage(from url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        defer { removeCachedImages(from: imageSource) }
        return loadCGImage(from: imageSource)
    }

    nonisolated static func loadCGImage(from data: Data) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        defer { removeCachedImages(from: imageSource) }
        return loadCGImage(from: imageSource)
    }

    nonisolated static func loadSonyEmbeddedPreview(from rawURL: URL) -> CGImage? {
        guard rawURL.pathExtension.localizedCaseInsensitiveCompare(SupportedFileType.arw.rawValue) == .orderedSame,
              let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: rawURL),
              let location = locations.fullJPEG ?? locations.preview ?? locations.thumbnail,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: location, from: rawURL)
        else {
            return nil
        }
        return loadCGImage(from: data)
    }

    private nonisolated static func loadCGImage(from imageSource: CGImageSource) -> CGImage? {
        let index = 0
        let maxPixelSize = maxPixelSize(for: imageSource, index: index)
        var decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        if let maxPixelSize {
            decodeOptions[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
        }
        return CGImageSourceCreateThumbnailAtIndex(imageSource, index, decodeOptions as CFDictionary)
    }

    private nonisolated static func maxPixelSize(for imageSource: CGImageSource, index: Int) -> Int? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else {
            return nil
        }
        let width = intValue(properties[kCGImagePropertyPixelWidth])
            ?? nestedIntValue(properties, dictionary: kCGImagePropertyExifDictionary, key: kCGImagePropertyExifPixelXDimension)
            ?? nestedIntValue(properties, dictionary: kCGImagePropertyTIFFDictionary, key: kCGImagePropertyPixelWidth)
        let height = intValue(properties[kCGImagePropertyPixelHeight])
            ?? nestedIntValue(properties, dictionary: kCGImagePropertyExifDictionary, key: kCGImagePropertyExifPixelYDimension)
            ?? nestedIntValue(properties, dictionary: kCGImagePropertyTIFFDictionary, key: kCGImagePropertyPixelHeight)

        guard let width, let height else { return nil }
        return max(width, height)
    }

    private nonisolated static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private nonisolated static func nestedIntValue(
        _ properties: [CFString: Any],
        dictionary: CFString,
        key: CFString,
    ) -> Int? {
        guard let nested = properties[dictionary] as? [CFString: Any] else { return nil }
        return intValue(nested[key])
    }

    private nonisolated static func removeCachedImages(from imageSource: CGImageSource) {
        for index in 0 ..< CGImageSourceGetCount(imageSource) {
            CGImageSourceRemoveCacheAtIndex(imageSource, index)
        }
    }
}
