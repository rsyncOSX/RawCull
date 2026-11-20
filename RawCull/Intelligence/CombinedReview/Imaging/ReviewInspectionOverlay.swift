import CoreGraphics
import Foundation

nonisolated enum ReviewInspectionOverlay {
    /// Transparent outside support: black grayscale background must not obscure the photograph.
    static func tint(_ mask: CGImage) throws -> CGImage {
        let foreground = try SubjectMaskForeground.decode(mask, width: mask.width, height: mask.height)
        var rgba = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for index in foreground.pixels.indices where foreground.pixels[index] > 16 {
            rgba[index * 4 + 1] = 180
            rgba[index * 4 + 2] = 255
            rgba[index * 4 + 3] = 110
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: mask.width, height: mask.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: mask.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw ReviewImageError.decodeFailed }
        return image
    }

    static func displayRect(_ rect: CGRect, sourceSize: CGSize, displaySize: CGSize) -> CGRect {
        rect.applying(CGAffineTransform(scaleX: displaySize.width / sourceSize.width, y: displaySize.height / sourceSize.height))
    }
}
