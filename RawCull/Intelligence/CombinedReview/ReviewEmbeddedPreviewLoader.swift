import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import RawParserKit

nonisolated struct ReviewEmbeddedPreview: Sendable {
    let image: CGImage
    let encodedSize: CGSize
    let orientation: UInt32
    var originalEncodedSize: CGSize?
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
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { continue }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let rawSource = CGImageSourceCreateWithURL(url as CFURL, nil)
            let rawProperties = rawSource.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] } ?? [:]
            let orientation = ((properties[kCGImagePropertyOrientation] ?? rawProperties[kCGImagePropertyOrientation]) as? NSNumber)?.uint32Value ?? 1
            if let preview = try Self.decode(source, width: pixelWidth, height: pixelHeight, orientation: orientation, request: request, embeddedOnly: false) {
                return preview
            }
        }
        // ImageIO embedded-only fallback. Never generate a RAW thumbnail or
        // substitute a sidecar. Native metadata supplies a conservative bound.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        return try Self.decode(source, width: pixelWidth, height: pixelHeight, orientation: orientation, request: request, embeddedOnly: true)
    }

    /// Decode without orientation first so RAW metadata can supply missing JPEG orientation.
    static func decode(_ source: CGImageSource, width: Int, height: Int, orientation: UInt32,
                       request: ReviewSourceRequest, embeddedOnly: Bool) throws -> ReviewEmbeddedPreview?
    {
        let maximumDimension = try ReviewImageSourceService.previewMaximumDimension(width: width, height: height, request: request)
        try Task.checkCancellation()
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: !embeddedOnly,
            kCGImageSourceCreateThumbnailFromImageIfAbsent: false,
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
        ] as CFDictionary) else { return nil }
        _ = try ReviewImageSourceService.admit(width: image.width, height: image.height, request: request)
        let encoded = CGSize(width: image.width, height: image.height)
        let oriented = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
        guard let normalized = ReviewImageSourceService.render(oriented, extent: oriented.extent) else { return nil }
        let original = CGSize(width: width, height: height)
        return ReviewEmbeddedPreview(image: normalized, encodedSize: encoded, orientation: orientation,
                                     originalEncodedSize: encoded == original ? nil : original)
    }
}
