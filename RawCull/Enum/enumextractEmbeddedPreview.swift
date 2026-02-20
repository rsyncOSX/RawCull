//
//  enumextractEmbeddedPreview.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

@preconcurrency import AppKit
import Foundation
import OSLog

enum enumextractEmbeddedPreview {
    
    /// Cannot use @concurrent nonisolated here, the func getWidth
    /// will not work then.
    /// The func extractEmbeddedPreview and func getWidth must be on the same isolation
    static func extractEmbeddedPreview(from arwURL: URL, fullSize: Bool = false) async -> CGImage? {
        // Target size for culling previews (width or height)
        // The system will resize the image to fit within this box during extraction
        // Use maxThumbnailSize = 0 to disable downsampling and keep original embedded JPEG
        let maxThumbnailSize: CGFloat = fullSize ? 8640 : 4320 // Set to 0 to disable downsampling

        // Downsampling to 4320 is on Silicon fairly quick and a sweet spot for culling

        guard let imageSource = CGImageSourceCreateWithURL(arwURL as CFURL, nil) else {
            Logger.process.warning("Failed to create image source")
            return nil
        }

        let imageCount = CGImageSourceGetCount(imageSource)
        Logger.process.debugThreadOnly("ExtractEmbeddedPreview: found \(imageCount) images in ARW file")

        var targetIndex: Int = -1
        var targetWidth = 0

        // 1. Find the LARGEST JPEG available
        for index in 0 ..< imageCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else {
                Logger.process.debugMessageOnly("ExtractEmbeddedPreview: Index \(index) - Failed to get properties")
                continue
            }

            // Detect JPEG
            let hasJFIF = (properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
            let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let compression = tiffDict?[kCGImagePropertyTIFFCompression] as? Int
            let isJPEG = hasJFIF || (compression == 6)

            if let width = getWidth(from: properties) {
                let typeStr = isJPEG ? "JPEG" : "Other"
                let message = "ExtractEmbeddedPreview: Index \(index) - \(typeStr) \(width)px wide (compression=\(compression ?? -1))"
                Logger.process.debugMessageOnly(message)

                // We track the widest JPEG found to get the best quality source
                if isJPEG, width > targetWidth {
                    targetWidth = width
                    targetIndex = index
                }
            } else {
                Logger.process.debugMessageOnly("ExtractEmbeddedPreview: Index \(index) - Could not determine width")
            }
        }

        // If no JPEG found, we are out of luck
        guard targetIndex != -1 else {
            Logger.process.warning("ExtractEmbeddedPreview: No JPEG found in file")
            return nil
        }

        Logger.process.info(
            "ExtractEmbeddedPreview: Selected JPEG at index \(targetIndex) (\(targetWidth)px). Target: \(maxThumbnailSize)"
        )

        // 2. Decide: Downsample or Decode Directly?
        // We only downsample if the source image is LARGER than our desired maxThumbnailSize.
        // If the source is smaller (e.g. a 2048px preview inside the ARW), we keep it as is (don't upscale).

        let requiresDownsampling = CGFloat(targetWidth) > maxThumbnailSize
        if requiresDownsampling {
            Logger.process.info("ExtractEmbeddedPreview: Downsampling to \(maxThumbnailSize)px")
        } else {
            Logger.process.info("ExtractEmbeddedPreview: Using original preview size (\(targetWidth)px)")
        }

        // Capture needed values by value to satisfy @Sendable requirements
        let selectedIndex = targetIndex
        let shouldDownsample = requiresDownsampling
        let maxSize = maxThumbnailSize

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            DispatchQueue.global(qos: .utility).async { [imageSource, selectedIndex, shouldDownsample, maxSize] in
                let result: CGImage?

                // Decode the image first
                let decodeOptions: [CFString: Any] = [
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceShouldAllowFloat: false
                ]
                let decodeDict = decodeOptions as CFDictionary
                guard let decodedImage = CGImageSourceCreateImageAtIndex(imageSource, selectedIndex, decodeDict) else {
                    continuation.resume(returning: nil)
                    return
                }

                if shouldDownsample {
                    // Manually resize the decoded image to the target size
                    result = self.resizeImage(decodedImage, maxPixelSize: maxSize)
                } else {
                    // Use as-is
                    result = decodedImage
                }

                continuation.resume(returning: result)
            }
        }
    }

    private nonisolated static func getWidth(from properties: [CFString: Any]) -> Int? {
        // Try Root
        if let width = properties[kCGImagePropertyPixelWidth] as? Int { return width }
        if let width = properties[kCGImagePropertyPixelWidth] as? Double { return Int(width) }

        // Try EXIF Dictionary
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Int { return width }
            if let width = exif[kCGImagePropertyExifPixelXDimension] as? Double { return Int(width) }
        }

        return nil
    }
    
    /// Resizes a CGImage to fit within maxPixelSize (respecting aspect ratio)
    /// - Parameters:
    ///   - image: The image to resize
    ///   - maxPixelSize: Maximum width or height (whichever is larger)
    /// - Returns: Resized CGImage, or nil if resizing fails
    private static nonisolated func resizeImage(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage? {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)

        let scale = min(maxPixelSize / originalWidth, maxPixelSize / originalHeight)
        guard scale < 1.0 else { return image } // Already smaller, no resize needed

        let newWidth = Int(originalWidth * scale)
        let newHeight = Int(originalHeight * scale)

        guard let colorSpace = image.colorSpace,
              let context = CGContext(data: nil,
                                      width: newWidth,
                                      height: newHeight,
                                      bitsPerComponent: image.bitsPerComponent,
                                      bytesPerRow: 0,
                                      space: colorSpace,
                                      bitmapInfo: image.bitmapInfo.rawValue)
        else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        return context.makeImage()
    }
    
}
