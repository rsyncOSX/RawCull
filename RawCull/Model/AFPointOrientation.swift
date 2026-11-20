import CoreGraphics
import Foundation
import ImageIO

/// Camera AF metadata is recorded in sensor (unrotated) coordinates, while every
/// image the app analyses or displays is decoded upright. This maps a normalized
/// sensor point into the oriented frame so all consumers share one coordinate space.
nonisolated enum AFPointOrientation {
    /// EXIF orientation of the primary image, or 1 when the file carries none.
    /// Nil only when the file cannot be opened.
    static func orientation(for url: URL) -> UInt32? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
            ?? (tiff?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.uint32Value ?? 1
    }

    /// Maps a normalized sensor point to the upright image for EXIF orientations 1–8.
    /// Unknown orientations leave the point unchanged.
    static func oriented(_ point: CGPoint, orientation: UInt32) -> CGPoint {
        let x = point.x, y = point.y
        return switch orientation {
        case 2: CGPoint(x: 1 - x, y: y)
        case 3: CGPoint(x: 1 - x, y: 1 - y)
        case 4: CGPoint(x: x, y: 1 - y)
        case 5: CGPoint(x: y, y: x)
        case 6: CGPoint(x: 1 - y, y: x)
        case 7: CGPoint(x: 1 - y, y: 1 - x)
        case 8: CGPoint(x: y, y: 1 - x)
        default: point
        }
    }

    /// True when the orientation swaps width and height.
    static func transposes(_ orientation: UInt32) -> Bool {
        (5 ... 8).contains(orientation)
    }
}
