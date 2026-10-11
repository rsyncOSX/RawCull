import CoreGraphics
import Foundation

/// Source-normalized masks are the registration authority for crop support.
/// Producer boxes remain audit evidence; no global origin flip is inferred.
nonisolated struct ReviewMaskRegistration: Codable, Equatable, Sendable {
    static let version = "registered-foreground-v1"
    let version: String
    let sourceIdentity: String
    let producerBounds: CGRect
    let foregroundBounds: CGRect
    let maximumBoundsDisagreementPixels: Double
    let tolerancePixels: Double
    let touchesSourceEdge: Bool
    let transform: String

    static func make(mask: CGImage, source: ReviewImageSource, producerBounds: CGRect) throws -> Self {
        let decoded = try SubjectMaskForeground.decode(mask, width: source.image.width, height: source.image.height)
        guard let bounds = decoded.bounds else { throw SubjectMaskDecodingError.emptyForeground }
        guard producerBounds.isFiniteReviewRect else { throw ReviewImageError.invalidGeometry }
        let producer = CGRect(x: producerBounds.minX * CGFloat(decoded.width), y: producerBounds.minY * CGFloat(decoded.height),
                              width: producerBounds.width * CGFloat(decoded.width), height: producerBounds.height * CGFloat(decoded.height))
        let disagreement = [abs(bounds.minX - producer.minX), abs(bounds.minY - producer.minY),
                            abs(bounds.maxX - producer.maxX), abs(bounds.maxY - producer.maxY)].max() ?? 0
        return .init(version: version, sourceIdentity: source.metadata.identity, producerBounds: producerBounds,
                     foregroundBounds: bounds, maximumBoundsDisagreementPixels: Double(disagreement),
                     tolerancePixels: 1, touchesSourceEdge: bounds.minX == 0 || bounds.minY == 0 || bounds.maxX == CGFloat(decoded.width) || bounds.maxY == CGFloat(decoded.height),
                     transform: "identity-source-normalized-raster; bounds from foreground, not producer box")
    }

    var warning: String? {
        maximumBoundsDisagreementPixels > tolerancePixels
            ? "Producer bounds differ from foreground by \(maximumBoundsDisagreementPixels) source pixels (tolerance \(tolerancePixels)); crop bounds were recomputed."
            : nil
    }

    func normalizedBounds(width: Int, height: Int) -> CGRect {
        foregroundBounds.applying(CGAffineTransform(scaleX: 1 / CGFloat(width), y: 1 / CGFloat(height)))
    }

    static func retainedFraction(_ foreground: SubjectMaskForeground, in rect: CGRect) -> Double {
        guard foreground.foregroundCount > 0 else { return 0 }
        var retained = 0
        for y in 0 ..< foreground.height {
            for x in 0 ..< foreground.width where foreground.pixels[y * foreground.width + x] > 16 {
                if rect.contains(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)) { retained += 1 }
            }
        }
        return Double(retained) / Double(foreground.foregroundCount)
    }
}

nonisolated struct ReviewCropSupport: Codable, Equatable, Sendable {
    let registrationVersion: String
    let subjectForegroundRetained: Double
    let encoderForegroundRetained: Double
    let sourceEdgeContact: Bool
    let anatomicalSupport: String
    var qualifiesWholeSubject: Bool { subjectForegroundRetained == 1 && encoderForegroundRetained == 1 }
}
