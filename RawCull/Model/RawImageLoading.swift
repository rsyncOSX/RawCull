import AppKit
import CoreGraphics
import Foundation
import RawParserKit

nonisolated struct RawImageFileMetadata: Sendable {
    let exifMetadata: ExifMetadata
    let focusLocation: String?
    let focusPoint: CGPoint?
}

nonisolated protocol RawImageLoading: Sendable {
    func fileMetadata(for url: URL) async -> RawImageFileMetadata?
    func exifMetadata(for url: URL) async -> ExifMetadata?
    func thumbnailCGImage(for url: URL, maxPixelSize: Int) async -> CGImage?
    func thumbnailImage(for url: URL, maxPixelSize: Int) async -> NSImage?
    func previewCGImage(for url: URL) async -> CGImage?
}

extension RawImageLoading {
    nonisolated func exifMetadata(for url: URL) async -> ExifMetadata? {
        await fileMetadata(for: url)?.exifMetadata
    }
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
            focalLength: metadata.focalLength,
            aperture: metadata.aperture,
            apertureValue: metadata.apertureValue,
            iso: metadata.isoValue.map { "ISO \($0)" } ?? metadata.iso.map(Self.isoDescription(from:)),
            isoValue: metadata.isoValue,
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
