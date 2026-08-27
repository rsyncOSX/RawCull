import AppKit
import CoreGraphics
import Foundation
import ImageIO
import RawParserKit

nonisolated struct RawImageFileMetadata: Sendable {
    let exifMetadata: ExifMetadata
    let captureDate: Date?
    let captureTimeZoneOffsetSeconds: Int?
    let focusLocation: String?
    let focusPoint: CGPoint?
}

nonisolated protocol RawImageLoading: Sendable {
    func fileMetadata(for url: URL) async -> RawImageFileMetadata?
    func thumbnailCGImage(for url: URL, maxPixelSize: Int) async -> CGImage?
    func thumbnailImage(for url: URL, maxPixelSize: Int) async -> NSImage?
    func previewCGImage(for url: URL) async -> CGImage?
    func embeddedPreviewJPEGData(
        for url: URL,
        matchingPixelWidth pixelWidth: Int,
        height pixelHeight: Int,
    ) async -> Data?
}

nonisolated enum RawImageLoadingError: Error {
    case invalidSource
    case generationFailed
}

nonisolated enum RawImageLoadingConstants {
    static let jpegExtension = RawParserKit.SupportedFileType.jpg.rawValue
}

nonisolated struct RawParserKitImageLoader: RawImageLoading {
    static let shared = RawParserKitImageLoader()

    func fileMetadata(for url: URL) async -> RawImageFileMetadata? {
        guard let metadata = await RawParserKit.RawImageLoader.shared.metadata(for: url) else { return nil }
        let exifMetadata = ExifMetadata(
            shutterSpeed: metadata.exposure,
            exposureTimeSeconds: metadata.exposureTimeSeconds,
            focalLength: metadata.focalLength,
            focalLengthMM: metadata.focalLengthMM,
            aperture: metadata.aperture,
            apertureValue: metadata.apertureValue,
            iso: metadata.isoValue.map { "ISO \($0)" } ?? metadata.iso.map(Self.isoDescription(from:)),
            isoValue: metadata.isoValue,
            exposureCompensationEV: metadata.exposureCompensationEV,
            camera: metadata.camera,
            lensModel: metadata.lens,
            rawFileType: metadata.rawFileType,
            rawSizeClass: metadata.rawSizeClass,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
        )
        let normalizedFocusPoint = metadata.focusPoint.map {
            CGPoint(x: $0.normalizedX, y: $0.normalizedY)
        }
        return RawImageFileMetadata(
            exifMetadata: exifMetadata,
            captureDate: metadata.captureDate,
            captureTimeZoneOffsetSeconds: metadata.captureTimeZoneOffsetSeconds,
            focusLocation: Self.focusLocation(from: metadata),
            focusPoint: normalizedFocusPoint,
        )
    }

    func thumbnailCGImage(for url: URL, maxPixelSize: Int) async -> CGImage? {
        await RawParserKit.RawImageLoader.shared.thumbnailCGImage(
            for: url,
            maxPixelSize: maxPixelSize,
        )
    }

    func thumbnailImage(for url: URL, maxPixelSize: Int) async -> NSImage? {
        await RawParserKit.RawImageLoader.shared.thumbnail(
            for: url,
            maxPixelSize: maxPixelSize,
        )
    }

    func previewCGImage(for url: URL) async -> CGImage? {
        await RawParserKit.RawImageLoader.shared.previewImage(for: url)
    }

    /// Returns the camera-authored JPEG bytes only when they match the preview
    /// that RawParserKit decoded. This avoids a second lossy JPEG encode while
    /// preserving the existing preview-selection and sizing behavior.
    @concurrent
    func embeddedPreviewJPEGData(
        for url: URL,
        matchingPixelWidth pixelWidth: Int,
        height pixelHeight: Int,
    ) async -> Data? {
        guard !Task.isCancelled else { return nil }

        switch url.pathExtension.lowercased() {
        case SupportedFileType.arw.rawValue:
            guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) else {
                return nil
            }
            for location in [locations.fullJPEG, locations.preview, locations.thumbnail].compactMap(\.self) {
                guard !Task.isCancelled else { return nil }
                if let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: location, from: url),
                   Self.jpegData(data, matchesPixelWidth: pixelWidth, height: pixelHeight) {
                    return data
                }
            }
        case SupportedFileType.nef.rawValue:
            guard let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url) else {
                return nil
            }
            for location in [locations.preview, locations.ifd1JPEG].compactMap(\.self) {
                guard !Task.isCancelled else { return nil }
                if let data = NikonMakerNoteParser.readEmbeddedJPEGData(at: location, from: url),
                   Self.jpegData(data, matchesPixelWidth: pixelWidth, height: pixelHeight) {
                    return data
                }
            }
        default:
            return nil
        }
        return nil
    }

    private static func jpegData(_ data: Data, matchesPixelWidth pixelWidth: Int, height pixelHeight: Int) -> Bool {
        guard let dimensions = jpegPixelDimensions(from: data) else { return false }
        return (dimensions.width == pixelWidth && dimensions.height == pixelHeight)
            || (dimensions.width == pixelHeight && dimensions.height == pixelWidth)
    }

    private static func jpegPixelDimensions(from data: Data) -> (width: Int, height: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        return (width, height)
    }

    private static func focusLocation(from metadata: RawImageMetadata) -> String? {
        guard let focusPoint = metadata.focusPoint,
              let width = metadata.pixelWidth,
              let height = metadata.pixelHeight,
              width > 0,
              height > 0
        else { return nil }

        let x = min(width, max(0, Int((focusPoint.normalizedX * Double(width)).rounded())))
        let y = min(height, max(0, Int((focusPoint.normalizedY * Double(height)).rounded())))
        return "\(width) \(height) \(x) \(y)"
    }

    private static func isoDescription(from value: String) -> String {
        value.hasPrefix("ISO ") ? value : "ISO \(value)"
    }
}
