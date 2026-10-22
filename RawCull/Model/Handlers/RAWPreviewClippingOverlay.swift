import AppKit
import RawCullCore
import SwiftUI

/// Display clipping only: never presented as a sensor-level recoverability mask.
nonisolated enum RAWPreviewClippingOverlay {
    @concurrent
    static func make(from image: CGImage) async -> CGImage? {
        guard !Task.isCancelled else { return nil }
        return autoreleasepool {
            dispatchPrecondition(condition: .notOnQueue(.main))
            let scale = min(1, 2048.0 / Double(max(image.width, image.height)))
            let width = max(1, Int(Double(image.width) * scale))
            let height = max(1, Int(Double(image.height) * scale))
            guard
                let context = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue,
                ), let data = context.data
            else { return nil }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = data.assumingMemoryBound(to: UInt8.self)
            for y in 0 ..< height {
                guard !Task.isCancelled else { return nil }
                for x in 0 ..< width {
                    let index = (y * width + x) * 4
                    let red = pixels[index]
                    let green = pixels[index + 1]
                    let blue = pixels[index + 2]
                    let highlight = min(red, green, blue) >= 254
                    let shadow = max(red, green, blue) <= 1
                    pixels[index] = highlight ? 180 : 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = shadow ? 180 : 0
                    pixels[index + 3] = highlight || shadow ? 180 : 0
                }
            }
            return context.makeImage()
        }
    }
}
