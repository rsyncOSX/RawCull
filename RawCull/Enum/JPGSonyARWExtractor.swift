//
//  JPGSonyARWExtractor.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

@preconcurrency import AppKit
import Foundation
import ImageIO
import OSLog

enum JPGSonyARWExtractor {
    static func jpgSonyARWExtractor(
        from arwURL: URL,
        fullSize: Bool = false,
    ) async -> CGImage? {
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            // Dispatch to GCD to prevent Thread Pool Starvation
            DispatchQueue.global(qos: .utility).async {
                // kCGImageSourceShouldCache: false on the SOURCE prevents ImageIO from
                // building a process-level cache for the ARW file itself. Without this,
                // calling CGImageSourceCopyPropertiesAtIndex on the RA16 RAW sensor
                // data sub-image can cause ImageIO to initialise its RA16 decoder and
                // allocate hundreds of MB that persist well after the imageSource is
                // released, because they are held in ImageIO's own internal cache rather
                // than being owned by the CGImageSource object.
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let imageSource = CGImageSourceCreateWithURL(arwURL as CFURL, sourceOptions) else {
                    Logger.process.warning("JPGSonyARWExtractor: Failed to create image source")
                    continuation.resume(returning: nil)
                    return
                }

                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex: Int = -1
                var targetWidth = 0

                // 1. Find the LARGEST JPEG available
                for index in 0 ..< imageCount {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(
                        imageSource,
                        index,
                        nil,
                    ) as? [CFString: Any]
                    else {
                        Logger.process.debugMessageOnly("JPGSonyARWExtractor: extractEmbeddedPreview(): Index \(index) - Failed to get properties")
                        continue
                    }

                    let hasJFIF = (properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
                    let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                    let compression = tiffDict?[kCGImagePropertyTIFFCompression] as? Int
                    let isJPEG = hasJFIF || (compression == 6)

                    if let width = getWidth(from: properties) {
                        if isJPEG, width > targetWidth {
                            targetWidth = width
                            targetIndex = index
                        }
                    }
                }

                var imageIOResult: CGImage?

                if targetIndex != -1 {
                    let requiresDownsampling = CGFloat(targetWidth) > maxThumbnailSize

                    // 2. Decode & Downsample using ImageIO directly
                    if requiresDownsampling {
                        Logger.process.info("JPGSonyARWExtractor: Native downsampling to \(maxThumbnailSize)px")

                        let options: [CFString: Any] = [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceCreateThumbnailWithTransform: true,
                            kCGImageSourceThumbnailMaxPixelSize: Int(maxThumbnailSize)
                        ]
                        imageIOResult = CGImageSourceCreateThumbnailAtIndex(imageSource, targetIndex, options as CFDictionary)
                    } else {
                        Logger.process.info("JPGSonyARWExtractor: Using original preview size (\(targetWidth)px)")

                        // kCGImageSourceShouldCache: false on the decode call prevents
                        // ImageIO from retaining the decoded pixel buffer separately from
                        // the returned CGImage.
                        let decodeOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                        imageIOResult = CGImageSourceCreateImageAtIndex(imageSource, targetIndex, decodeOptions)
                    }
                } else {
                    Logger.process.warning("JPGSonyARWExtractor: No JPEG found via ImageIO — trying binary fallback")
                }

                // Evict cache entries for ALL sub-images. Even with source-level caching
                // disabled, calling CGImageSourceCopyPropertiesAtIndex on the RA16 RAW
                // sub-image may have seeded residual entries in ImageIO's internal cache.
                // This belt-and-suspenders call ensures they are freed before imageSource
                // goes out of scope.
                for i in 0 ..< imageCount {
                    CGImageSourceRemoveCacheAtIndex(imageSource, i)
                }

                // Binary fallback for ARW 6.0 (RA16 decoder unsupported on this macOS version).
                // Reads the embedded full-resolution JPEG directly from the raw file bytes,
                // bypassing the RA16 decoder entirely.
                let finalResult: CGImage?
                if imageIOResult == nil {
                    finalResult = Self.binaryFallbackJPEG(from: arwURL, fullSize: fullSize, maxSize: maxThumbnailSize)
                    if finalResult == nil {
                        Logger.process.warning("JPGSonyARWExtractor: Binary fallback also failed for \(arwURL.lastPathComponent)")
                    }
                } else {
                    finalResult = imageIOResult
                }

                continuation.resume(returning: finalResult)
            }
        }
    }

    /// Binary fallback for ARW 6.0 files (e.g. Sony A7V) where the macOS RA16 decoder
    /// cannot decode the file. Extracts an embedded JPEG directly from the raw file bytes
    /// and decodes it as a plain JPEG, bypassing the RA16 path.
    private nonisolated static func binaryFallbackJPEG(
        from url: URL,
        fullSize: Bool,
        maxSize: CGFloat,
    ) -> CGImage? {
        guard let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: url) else { return nil }

        // For full-size export prefer the full JPEG; for thumbnails prefer the smaller preview.
        let loc = fullSize
            ? (locations.fullJPEG ?? locations.preview ?? locations.thumbnail)
            : (locations.preview ?? locations.fullJPEG ?? locations.thumbnail)

        guard let loc,
              let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url),
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
