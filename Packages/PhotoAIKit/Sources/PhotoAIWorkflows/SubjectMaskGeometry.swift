import CoreGraphics
import Foundation

public struct SubjectMaskGeometry: Equatable, Sendable {
    public let coverage: Float
    public let boundingBox: CGRect
    public let centroid: CGPoint
    public let isFresh: Bool

    public init(coverage: Float, boundingBox: CGRect, centroid: CGPoint, isFresh: Bool) {
        self.coverage = coverage
        self.boundingBox = boundingBox
        self.centroid = centroid
        self.isFresh = isFresh
    }

    public static func measure(
        mask: CGImage,
        sourceModificationDate: Date? = nil,
        cacheModificationDate: Date? = nil
    ) -> SubjectMaskGeometry {
        let width = mask.width
        let height = mask.height
        guard width > 0, height > 0 else {
            return SubjectMaskGeometry(
                coverage: 0,
                boundingBox: .zero,
                centroid: CGPoint(x: 0.5, y: 0.5),
                isFresh: true
            )
        }
        let alpha = alphaPlane(from: mask, width: width, height: height)
        let nonzero = alpha.enumerated().filter { $0.element > 0 }
        let coverage = Float(nonzero.count) / Float(width * height)

        var minX = width, maxX = -1, minY = height, maxY = -1
        var sumX = 0.0, sumY = 0.0, sumWeight = 0.0
        for (index, value) in nonzero {
            let x = index % width
            let y = index / width
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
            let weight = Double(value)
            sumX += Double(x) * weight
            sumY += Double(y) * weight
            sumWeight += weight
        }
        let box: CGRect = if maxX >= minX, maxY >= minY {
            CGRect(
                x: CGFloat(minX) / CGFloat(width),
                y: CGFloat(minY) / CGFloat(height),
                width: CGFloat(maxX - minX + 1) / CGFloat(width),
                height: CGFloat(maxY - minY + 1) / CGFloat(height)
            )
        } else { .zero }
        let centroid = sumWeight > 0
            ? CGPoint(x: (sumX / sumWeight) / Double(width), y: (sumY / sumWeight) / Double(height))
            : CGPoint(x: 0.5, y: 0.5)
        let isFresh = if let sourceModificationDate, let cacheModificationDate {
            cacheModificationDate >= sourceModificationDate
        } else { true }
        return SubjectMaskGeometry(
            coverage: coverage,
            boundingBox: box,
            centroid: centroid,
            isFresh: isFresh
        )
    }

    private static func alphaPlane(from image: CGImage, width: Int, height: Int) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
    }
}
