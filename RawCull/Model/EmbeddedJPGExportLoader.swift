import CoreGraphics
import Foundation
import ImageIO
import RawParserKit

nonisolated protocol EmbeddedJPGExportLoading: Sendable {
    func jpegData(for rawURL: URL) async -> Data?
}

/// Export reads the RAW's embedded image, never a sidecar or a display cache.
nonisolated struct EmbeddedJPGExportLoader: EmbeddedJPGExportLoading {
    @concurrent
    func jpegData(for rawURL: URL) async -> Data? {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [rawURL])
        defer { withExtendedLifetime(access) {} }
        guard !Task.isCancelled, let original = embeddedBytes(from: rawURL), !Task.isCancelled else { return nil }
        if hasStandaloneOrientation(original, rawURL: rawURL) {
            return original
        }
        // Some embedded JPEGs rely on orientation in the enclosing RAW.
        // Normalize those pixels before producing a standalone export.
        guard let image = OrientationNormalizedImageLoader.loadEmbeddedPreview(from: original, sourceURL: rawURL),
              !Task.isCancelled else { return nil }
        return SaveJPGImage.jpegData(from: image)
    }

    private func embeddedBytes(from url: URL) -> Data? {
        switch url.pathExtension.lowercased() {
        case "arw":
            guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) else { return nil }
            return firstJPEG([locations.fullJPEG, locations.preview, locations.thumbnail]) {
                SonyMakerNoteParser.readEmbeddedJPEGData(at: $0, from: url)
            }

        case "nef":
            guard let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url) else { return nil }
            return firstJPEG([locations.preview, locations.ifd1JPEG]) {
                NikonMakerNoteParser.readEmbeddedJPEGData(at: $0, from: url)
            }

        case "dng":
            guard let locations = DNGMakerNoteParser.embeddedJPEGLocations(from: url) else { return nil }
            return firstJPEG([locations.fullJPEG, locations.preview, locations.thumbnail]) {
                DNGMakerNoteParser.readEmbeddedJPEGData(at: $0, from: url)
            }

        default:
            return nil
        }
    }

    private func firstJPEG<Location>(_ locations: [Location?], read: (Location) -> Data?) -> Data? {
        for location in locations.compactMap({ $0 }) {
            guard !Task.isCancelled else { return nil }
            if let data = read(location),
               let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
               CGImageSourceGetType(source) as String? == "public.jpeg",
               CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil {
                return data
            }
        }
        return nil
    }

    private func hasStandaloneOrientation(_ data: Data, rawURL: URL) -> Bool {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let jpeg = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(jpeg, 0, options) as? [CFString: Any]
        else { return false }
        if properties[kCGImagePropertyOrientation] != nil {
            return true
        }
        guard let raw = CGImageSourceCreateWithURL(rawURL as CFURL, options),
              let sourceProperties = CGImageSourceCopyPropertiesAtIndex(raw, 0, options) as? [CFString: Any]
        else { return false }
        return (sourceProperties[kCGImagePropertyOrientation] as? Int ?? 1) == 1
    }
}
