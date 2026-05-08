//
//  JPGNikonNEFExtractor.swift
//  RawCull
//
//  Extracts the largest embedded JPEG from a Nikon NEF. First tries ImageIO;
//  falls back to a binary TIFF walk via `NikonMakerNoteParser` when ImageIO
//  fails to surface the preview JPEG (the common case for NEF, where the
//  full-res preview lives in a SubIFD chain rather than at a top-level
//  image index). Mirrors the shape of `JPGSonyARWExtractor`.
//

import CoreGraphics
import Foundation
import ImageIO
import OSLog

enum JPGNikonNEFExtractor {
    static func jpgNikonNEFExtractor(
        from nefURL: URL,
        fullSize: Bool = false,
    ) async -> CGImage? {
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            DispatchQueue.global(qos: .utility).async {
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let imageSource = CGImageSourceCreateWithURL(nefURL as CFURL, sourceOptions) else {
                    Logger.process.warning("JPGNikonNEFExtractor: failed to create image source")
                    continuation.resume(returning: nil)
                    return
                }

                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex: Int = -1
                var targetWidth = 0

                // 1. Find the LARGEST embedded JPEG across all sub-images.
                for index in 0 ..< imageCount {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(
                        imageSource, index, nil,
                    ) as? [CFString: Any] else { continue }

                    let hasJFIF = (properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
                    let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                    let compression = tiffDict?[kCGImagePropertyTIFFCompression] as? Int
                    let isJPEG = hasJFIF || (compression == 6)

                    if let width = getWidth(from: properties), isJPEG, width > targetWidth {
                        targetWidth = width
                        targetIndex = index
                    }
                }

                var imageIOResult: CGImage?
                if targetIndex != -1 {
                    let requiresDownsampling = CGFloat(targetWidth) > maxThumbnailSize
                    if requiresDownsampling {
                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: Int(maxThumbnailSize)
                        ]
                        imageIOResult = CGImageSourceCreateThumbnailAtIndex(imageSource, targetIndex, options as CFDictionary)
                    } else {
                        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                        imageIOResult = CGImageSourceCreateImageAtIndex(imageSource, targetIndex, decodeOptions)
                    }
                }

                for i in 0 ..< imageCount {
                    CGImageSourceRemoveCacheAtIndex(imageSource, i)
                }

                let finalResult: CGImage?
                if imageIOResult == nil {
                    finalResult = Self.binaryFallbackJPEG(from: nefURL, fullSize: fullSize, maxSize: maxThumbnailSize)
                    if finalResult == nil {
                        Logger.process.warning("JPGNikonNEFExtractor: binary fallback also failed for \(nefURL.lastPathComponent)")
                    }
                } else {
                    finalResult = imageIOResult
                }

                continuation.resume(returning: finalResult)
            }
        }
    }

    /// Binary fallback: walks the NEF's TIFF SubIFDs via `NikonMakerNoteParser`,
    /// reads the embedded JPEG bytes directly, and decodes them as a plain JPEG
    /// — bypassing any NEF-specific ImageIO path that may not surface the
    /// preview as a top-level image index.
    private nonisolated static func binaryFallbackJPEG(
        from url: URL,
        fullSize: Bool,
        maxSize: CGFloat,
    ) -> CGImage? {
        guard let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url) else { return nil }

        // For full-size export prefer the full-res SubIFD JPEG; for thumbnails
        // prefer IFD1 (smaller) to save decode cost.
        let loc = fullSize
            ? (locations.preview ?? locations.ifd1JPEG)
            : (locations.ifd1JPEG ?? locations.preview)

        guard let loc,
              let data = NikonMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
              let src = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxSize)
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private nonisolated static func getWidth(from properties: [CFString: Any]) -> Int? {
        if let width = properties[kCGImagePropertyPixelWidth] as? Int { return width }
        if let width = properties[kCGImagePropertyPixelWidth] as? Double { return Int(width) }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            if let width = tiff[kCGImagePropertyPixelWidth] as? Int { return width }
            if let width = tiff[kCGImagePropertyPixelWidth] as? Double { return Int(width) }
        }
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Int { return width }
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Double { return Int(width) }
        }
        return nil
    }
}
