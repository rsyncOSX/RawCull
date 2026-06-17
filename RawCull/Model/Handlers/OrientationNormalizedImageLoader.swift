import Foundation
import ImageIO
import RawParserKit

enum OrientationNormalizedImageLoader {
    // MARK: - Public API

    /// Loads a full-size CGImage with EXIF orientation applied.
    /// Uses direct decode + manual rotation — avoids CreateThumbnailFromImageAlways
    /// which forces a full bitmap decode even when ShouldCache is false.
    nonisolated static func loadCGImage(from url: URL) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }
        defer { removeCachedImages(from: imageSource) }
        return loadDirectImage(from: imageSource)
    }

    nonisolated static func loadCGImage(from data: Data) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        defer { removeCachedImages(from: imageSource) }
        return loadDirectImage(from: imageSource)
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

    // MARK: - Private

    /// Direct decode without thumbnail pipeline. Reads EXIF orientation and
    /// applies it via CGContext rotation, keeping peak memory to one bitmap
    /// rather than the two that CreateThumbnailFromImageAlways can produce.
    private nonisolated static func loadDirectImage(from imageSource: CGImageSource) -> CGImage? {
        let index = 0
        let decodeOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let image = CGImageSourceCreateImageAtIndex(imageSource, index,
                                                          decodeOptions as CFDictionary)
        else {
            return nil
        }

        let orientation = exifOrientation(from: imageSource, index: index)
        return applyOrientation(to: image, orientation: orientation)
    }

    private nonisolated static func exifOrientation(from imageSource: CGImageSource, index: Int) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil) as? [CFString: Any] else {
            return 1
        }
        // Orientation can live at the top level or inside the TIFF dictionary
        if let orientation = properties[kCGImagePropertyOrientation] as? Int {
            return orientation
        }
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
           let orientation = tiff[kCGImagePropertyTIFFOrientation] as? Int {
            return orientation
        }
        return 1 // default: no rotation
    }

    /// Applies EXIF orientation (1–8) by redrawing into a correctly sized CGContext.
    /// Returns the original image unchanged for orientation 1 (no-op).
    private nonisolated static func applyOrientation(to image: CGImage, orientation: Int) -> CGImage? {
        guard orientation != 1 else { return image }

        let w = image.width
        let h = image.height

        // For orientations 5–8 the image is transposed (width and height swap)
        let transposed = orientation >= 5
        let destWidth = transposed ? h : w
        let destHeight = transposed ? w : h

        guard let context = CGContext(
            data: nil,
            width: destWidth,
            height: destHeight,
            bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: image.bitmapInfo.rawValue,
        ) else { return image }

        context.interpolationQuality = .none

        // Apply the transform that corresponds to the EXIF orientation tag.
        // EXIF orientations are defined relative to the sensor's native readout;
        // the transforms below map each case to an upright image in screen space.
        switch orientation {
        case 2: // flip horizontal
            context.translateBy(x: CGFloat(destWidth), y: 0)
            context.scaleBy(x: -1, y: 1)

        case 3: // rotate 180
            context.translateBy(x: CGFloat(destWidth), y: CGFloat(destHeight))
            context.rotate(by: .pi)

        case 4: // flip vertical
            context.translateBy(x: 0, y: CGFloat(destHeight))
            context.scaleBy(x: 1, y: -1)

        case 5: // transpose (rotate 90 CCW + flip horizontal)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: -1, y: 1)

        case 6: // rotate 90 CW
            context.translateBy(x: CGFloat(destWidth), y: 0)
            context.rotate(by: .pi / 2)

        case 7: // transverse (rotate 90 CW + flip horizontal)
            context.translateBy(x: CGFloat(destWidth), y: CGFloat(destHeight))
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)

        case 8: // rotate 90 CCW
            context.translateBy(x: 0, y: CGFloat(destHeight))
            context.rotate(by: -.pi / 2)

        default:
            break
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)))
        return context.makeImage() ?? image
    }

    private nonisolated static func removeCachedImages(from imageSource: CGImageSource) {
        for index in 0 ..< CGImageSourceGetCount(imageSource) {
            CGImageSourceRemoveCacheAtIndex(imageSource, index)
        }
    }
}
