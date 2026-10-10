import CoreGraphics
import CryptoKit
import Foundation

nonisolated enum ReviewImageError: Error, LocalizedError {
    case invalidGeometry, decodeFailed, sourceChanged, memoryAdmissionDenied, unsupportedAlignment

    var errorDescription: String? {
        switch self {
        case .invalidGeometry: "The review source or crop has invalid dimensions."
        case .decodeFailed: "The selected review source could not be decoded."
        case .sourceChanged: "The image changed during source preparation. Rerun with current settings."
        case .memoryAdmissionDenied:
            "The full-resolution source exceeds Combined Review's memory limits. For a RAW file, choose High-quality preview, then Rerun with current settings. Resume keeps the saved source setting."
        case .unsupportedAlignment: "The review source and mask cannot be aligned safely."
        }
    }
}

/// All public coordinates are orientation-normalized, top-left-origin pixels.
/// Mask coordinates are normalized top-left coordinates, not Vision's bottom-left coordinates.
nonisolated struct ReviewCoordinateSpace: Equatable, Sendable {
    let size: CGSize

    init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else { throw ReviewImageError.invalidGeometry }
        size = CGSize(width: width, height: height)
    }

    init(image: CGImage) {
        size = CGSize(width: image.width, height: image.height)
    }

    private init(validatedSize: CGSize) {
        size = validatedSize
    }

    var transposed: Self {
        Self(validatedSize: CGSize(width: size.height, height: size.width))
    }

    var bounds: CGRect {
        CGRect(origin: .zero, size: size)
    }

    func map(_ rect: CGRect, to destination: Self) throws -> CGRect {
        guard rect.isFiniteReviewRect else { throw ReviewImageError.invalidGeometry }
        return rect.applying(CGAffineTransform(
            scaleX: destination.size.width / size.width,
            y: destination.size.height / size.height,
        ))
    }

    func sourceRect(fromNormalized rect: CGRect) throws -> CGRect {
        guard rect.isFiniteReviewRect, CGRect(x: 0, y: 0, width: 1, height: 1).contains(rect) else {
            throw ReviewImageError.invalidGeometry
        }
        return rect.applying(CGAffineTransform(scaleX: size.width, y: size.height))
    }
}

nonisolated extension CGRect {
    var isFiniteReviewRect: Bool {
        [origin.x, origin.y, size.width, size.height].allSatisfy(\.isFinite)
            && width > 0 && height > 0
    }
}

/// Geometry strategy must come from a content/runtime-matched verified contract.
/// This is a geometry description, not an inference preprocessor or model qualification.
nonisolated struct ReviewEncoderGeometry: Equatable, Sendable {
    nonisolated enum Strategy: String, Sendable { case stretch, shortestSideCenterCrop }
    let width: Int
    let height: Int
    let strategy: Strategy

    func trace(crop: CGRect) throws -> ReviewEncoderTrace {
        guard width > 0, height > 0, crop.isFiniteReviewRect else {
            throw ReviewImageError.invalidGeometry
        }
        switch strategy {
        case .stretch:
            return ReviewEncoderTrace(retainedSourceRect: crop,
                                      scaleX: CGFloat(width) / crop.width,
                                      scaleY: CGFloat(height) / crop.height,
                                      encoderSize: CGSize(width: width, height: height))

        case .shortestSideCenterCrop:
            // Match the pinned CLIP processor: integer resize followed by integer center crop.
            guard width == height else { throw ReviewImageError.invalidGeometry }
            let resizedWidth = crop.width > crop.height
                ? Int(Double(width) * Double(crop.width) / Double(crop.height)) : width
            let resizedHeight = crop.width > crop.height
                ? height : Int(Double(height) * Double(crop.height) / Double(crop.width))
            let sx = CGFloat(resizedWidth) / crop.width
            let sy = CGFloat(resizedHeight) / crop.height
            let retained = CGRect(x: crop.minX + CGFloat((resizedWidth - width) / 2) / sx,
                                  y: crop.minY + CGFloat((resizedHeight - height) / 2) / sy,
                                  width: CGFloat(width) / sx, height: CGFloat(height) / sy)
            return ReviewEncoderTrace(retainedSourceRect: retained, scaleX: sx, scaleY: sy,
                                      encoderSize: CGSize(width: width, height: height))
        }
    }
}

nonisolated struct ReviewEncoderTrace: Equatable, Sendable {
    let retainedSourceRect: CGRect
    let scaleX: CGFloat
    let scaleY: CGFloat
    let encoderSize: CGSize
    var upscalesSource: Bool {
        scaleX > 1 || scaleY > 1
    }

    func encoderPoint(fromSource point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - retainedSourceRect.minX) * scaleX,
                y: (point.y - retainedSourceRect.minY) * scaleY)
    }

    func sourcePoint(fromEncoder point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / scaleX + retainedSourceRect.minX,
                y: point.y / scaleY + retainedSourceRect.minY)
    }
}

nonisolated struct ReviewRegion: Sendable {
    let id: String
    let sourceID: String
    let purpose: String
    let requestedRect: CGRect
    let paddedRect: CGRect
    let sourceRect: CGRect
    let edgeClipped: Bool
    let encoder: ReviewEncoderTrace
    var intendedRegionRetained: Bool {
        encoder.retainedSourceRect.contains(requestedRect)
    }

    static func make(sourceID: String, space: ReviewCoordinateSpace, rect: CGRect,
                     padding: CGFloat = 0.15, purpose: String,
                     encoder: ReviewEncoderGeometry) throws -> Self
    {
        guard rect.isFiniteReviewRect, padding.isFinite, padding >= 0, padding <= 1,
              space.bounds.contains(rect), !purpose.isEmpty
        else {
            throw ReviewImageError.invalidGeometry
        }
        let padded = rect.insetBy(dx: -rect.width * padding, dy: -rect.height * padding)
        let clipped = padded.intersection(space.bounds).integral.intersection(space.bounds)
        let trace = try encoder.trace(crop: clipped)
        let values = [rect.minX, rect.minY, rect.width, rect.height, padding,
                      clipped.minX, clipped.minY, clipped.width, clipped.height]
        let key = "region-v1|\(sourceID)|\(purpose)|" + values.map { String(Double($0)) }.joined(separator: "|")
        let id = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self(id: id, sourceID: sourceID, purpose: purpose, requestedRect: rect, paddedRect: padded,
                    sourceRect: clipped, edgeClipped: !space.bounds.contains(padded), encoder: trace)
    }
}

/// EXIF edge-coordinate transform. Pixel centers use x+0.5/y+0.5.
nonisolated struct ReviewOrientationTransform: Equatable, Sendable {
    let encodedSpace: ReviewCoordinateSpace
    let orientation: UInt32

    init(width: Int, height: Int, orientation: UInt32) throws {
        guard (1 ... 8).contains(orientation) else { throw ReviewImageError.invalidGeometry }
        encodedSpace = try ReviewCoordinateSpace(width: width, height: height)
        self.orientation = orientation
    }

    var normalizedSpace: ReviewCoordinateSpace {
        orientation >= 5 ? encodedSpace.transposed : encodedSpace
    }

    var transform: CGAffineTransform {
        let pixelWidth = encodedSpace.size.width, pixelHeight = encodedSpace.size.height
        switch orientation {
        case 2: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: pixelWidth, ty: 0)
        case 3: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: pixelWidth, ty: pixelHeight)
        case 4: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: pixelHeight)
        case 5: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case 6: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: pixelHeight, ty: 0)
        case 7: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: pixelHeight, ty: pixelWidth)
        case 8: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: pixelWidth)
        default: return .identity
        }
    }

    func normalizedRect(fromEncoded rect: CGRect) throws -> CGRect {
        guard rect.isFiniteReviewRect, encodedSpace.bounds.contains(rect) else { throw ReviewImageError.invalidGeometry }
        return rect.applying(transform)
    }

    func encodedRect(fromNormalized rect: CGRect) throws -> CGRect {
        guard rect.isFiniteReviewRect, normalizedSpace.bounds.contains(rect) else { throw ReviewImageError.invalidGeometry }
        return rect.applying(transform.inverted())
    }
}
