//
//  PreviewExtractor.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

@preconcurrency import AppKit
import Foundation
import ImageIO
import OSLog

enum enumPreviewExtractor {
    static func extractEmbeddedPreview(
        from arwURL: URL,
        fullSize: Bool = false
    ) async -> CGImage? {
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            // Dispatch to GCD to prevent Thread Pool Starvation
            DispatchQueue.global(qos: .utility).async {

                guard let imageSource = CGImageSourceCreateWithURL(arwURL as CFURL, nil) else {
                    Logger.process.warning("PreviewExtractor: Failed to create image source")
                    continuation.resume(returning: nil)
                    return
                }

                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex: Int = -1
                var targetWidth = 0

                // 1. Find the LARGEST JPEG available
                for index in 0 ..< imageCount {
                    guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else {
                        Logger.process.debugMessageOnly("enum: extractEmbeddedPreview(): Index \(index) - Failed to get properties")
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

                guard targetIndex != -1 else {
                    Logger.process.warning("PreviewExtractor: No JPEG found in file")
                    continuation.resume(returning: nil)
                    return
                }

                let requiresDownsampling = CGFloat(targetWidth) > maxThumbnailSize
                let result: CGImage?

                // 2. Decode & Downsample using ImageIO directly
                if requiresDownsampling {
                    Logger.process.info("PreviewExtractor: Native downsampling to \(maxThumbnailSize)px")

                    // THESE ARE THE MAGIC OPTIONS that replace your resizeImage() function
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: Int(maxThumbnailSize)
                    ]

                    result = CGImageSourceCreateThumbnailAtIndex(imageSource, targetIndex, options as CFDictionary)
                } else {
                    Logger.process.info("PreviewExtractor: Using original preview size (\(targetWidth)px)")

                    // Your original standard decoding options
                    let decodeOptions: [CFString: Any] = [
                        kCGImageSourceShouldCache: true,
                        kCGImageSourceShouldCacheImmediately: true
                    ]

                    result = CGImageSourceCreateImageAtIndex(imageSource, targetIndex, decodeOptions as CFDictionary)
                }

                continuation.resume(returning: result)
            }
        }
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
