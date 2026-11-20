import CoreGraphics
import Foundation

/// Explicit interpretation of a registered CGImage raster. No resizing or local
/// coordinate flips are permitted. Registration to image content is a separate gate.
nonisolated struct SubjectMaskContract: Codable, Equatable, Sendable {
    enum Channel: String, Codable, Sendable { case grayscaleIntensity, alpha }
    static let version = "mask-foreground-v1"
    let version: String
    let channel: Channel
    let width: Int
    let height: Int
    let sourceIdentity: String
    let origin: String
    let polarity: String
    let threshold: Int
    let interpolation: String

    static func make(mask: CGImage, sourceIdentity: String) throws -> Self {
        let channel = try SubjectMaskForeground.channel(mask)
        return .init(version: version, channel: channel, width: mask.width, height: mask.height,
                     sourceIdentity: sourceIdentity, origin: "top-left-source-raster", polarity: "white-or-opaque-foreground",
                     threshold: 16, interpolation: "none-no-resize")
    }

    func validate(mask: CGImage, sourceIdentity: String) throws {
        guard try self == (Self.make(mask: mask, sourceIdentity: sourceIdentity)) else {
            throw SubjectMaskDecodingError.unsafeRegistration
        }
    }
}

nonisolated enum SubjectMaskDecodingError: String, Error, LocalizedError {
    case unsupportedEncoding, unsafeRegistration, emptyForeground, insufficientUsablePixels
    var errorDescription: String? {
        "Subject mask: \(rawValue)"
    }
}

nonisolated struct SubjectMaskForeground: Sendable {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let foregroundCount: Int
    let bounds: CGRect?
    var totalCoverage: Float {
        Float(foregroundCount) / Float(pixels.count)
    }

    var suspectNearFullOccupancy: Bool {
        totalCoverage >= 0.95
    }

    static func channel(_ mask: CGImage) throws -> SubjectMaskContract.Channel {
        guard !mask.isMask, mask.bitsPerComponent == 8, mask.width > 0, mask.height > 0,
              mask.width <= Int.max / mask.height / 4 else { throw SubjectMaskDecodingError.unsupportedEncoding }
        if mask.colorSpace?.model == .monochrome, mask.alphaInfo == .none, mask.bitsPerPixel == 8 {
            return .grayscaleIntensity
        }
        if mask.alphaInfo == .alphaOnly || (mask.colorSpace?.model == .rgb &&
            [.first, .last, .premultipliedFirst, .premultipliedLast].contains(mask.alphaInfo)) {
            return .alpha
        }
        throw SubjectMaskDecodingError.unsupportedEncoding
    }

    static func decode(_ mask: CGImage, width: Int, height: Int) throws -> Self {
        guard mask.width == width, mask.height == height else { throw SubjectMaskDecodingError.unsafeRegistration }
        let channel = try channel(mask)
        var foreground: [UInt8]
        switch channel {
        case .grayscaleIntensity:
            // Read samples, not color-managed luminance. Respect padded row stride.
            guard mask.decode == nil, let data = mask.dataProvider?.data,
                  CFDataGetLength(data) >= mask.bytesPerRow * height,
                  let bytes = CFDataGetBytePtr(data) else { throw SubjectMaskDecodingError.unsupportedEncoding }
            foreground = (0 ..< height).flatMap { y in
                Array(UnsafeBufferPointer(start: bytes + y * mask.bytesPerRow, count: width))
            }

        case .alpha:
            var rgba = [UInt8](repeating: 0, count: width * height * 4)
            guard let context = CGContext(data: &rgba, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw SubjectMaskDecodingError.unsupportedEncoding }
            context.interpolationQuality = .none
            context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
            foreground = stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }
        var count = 0, minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0 ..< height {
            if y & 0x3F == 0 {
                try Task.checkCancellation()
            }
            for x in 0 ..< width where foreground[y * width + x] > 16 {
                count += 1
                minX = min(minX, x); minY = min(minY, y)
                maxX = max(maxX, x); maxY = max(maxY, y)
            }
        }
        return .init(pixels: foreground, width: width, height: height, foregroundCount: count,
                     bounds: count == 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }
}
