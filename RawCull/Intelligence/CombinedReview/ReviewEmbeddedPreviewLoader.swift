import CoreGraphics
import Foundation
import ImageIO
import RawParserKit

nonisolated struct ReviewEmbeddedPreview: Sendable {
    let image: CGImage
    let encodedSize: CGSize
    let orientation: UInt32
}

nonisolated protocol ReviewEmbeddedPreviewLoading: Sendable {
    func load(_ request: ReviewSourceRequest) throws -> ReviewEmbeddedPreview?
}

/// Uses camera JPEG locations and orientation handling from RawParserKit, but
/// bypasses its sidecar-first preview cache. Selects the largest decodable preview.
nonisolated struct ReviewEmbeddedPreviewLoader: ReviewEmbeddedPreviewLoading {
    func load(_ request: ReviewSourceRequest) throws -> ReviewEmbeddedPreview? {
        let url = request.url
        var candidates: [Data] = []
        switch url.pathExtension.lowercased() {
        case "arw":
            if let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) {
                for location in [locations.fullJPEG, locations.preview, locations.thumbnail].compactMap(\.self) {
                    try Task.checkCancellation()
                    if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: location, from: url) {
                        candidates.append(data)
                    }
                }
            }
        case "nef":
            if let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url) {
                for location in [locations.preview, locations.ifd1JPEG].compactMap(\.self) {
                    try Task.checkCancellation()
                    if let data = NikonMakerNoteParser.readEmbeddedJPEGData(at: location, from: url) {
                        candidates.append(data)
                    }
                }
            }
        default: break
        }
        let sized = candidates.compactMap { data -> (Data, Int, Int)? in
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  pixelWidth > 0, pixelHeight > 0 else { return nil }
            return (data, pixelWidth, pixelHeight)
        }.sorted { Double($0.1) * Double($0.2) > Double($1.1) * Double($1.2) }
        for (data, pixelWidth, pixelHeight) in sized {
            // Do not silently choose a smaller source to fit the budget.
            _ = try ReviewImageSourceService.admit(width: pixelWidth, height: pixelHeight, request: request)
            try Task.checkCancellation()
            if let image = OrientationNormalizedImageLoader.loadEmbeddedPreview(from: data, sourceURL: url) {
                let source = CGImageSourceCreateWithData(data as CFData, nil)!
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let rawSource = CGImageSourceCreateWithURL(url as CFURL, nil)
                let rawProperties = rawSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
                let orientation = ((properties[kCGImagePropertyOrientation] ?? rawProperties[kCGImagePropertyOrientation]) as? NSNumber)?.uint32Value ?? 1
                return ReviewEmbeddedPreview(image: image, encodedSize: CGSize(width: pixelWidth, height: pixelHeight), orientation: orientation)
            }
        }
        // ImageIO embedded-only fallback. Never generate a RAW thumbnail or
        // substitute a sidecar. Native metadata supplies a conservative bound.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        _ = try ReviewImageSourceService.admit(width: pixelWidth, height: pixelHeight, request: request)
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: false,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(pixelWidth, pixelHeight),
        ] as CFDictionary) else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        let encoded = orientation >= 5 ? CGSize(width: image.height, height: image.width) : CGSize(width: image.width, height: image.height)
        return ReviewEmbeddedPreview(image: image, encodedSize: encoded, orientation: orientation)
    }
}
