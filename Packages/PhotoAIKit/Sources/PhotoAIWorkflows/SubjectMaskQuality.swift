import CoreGraphics
import Foundation

public enum SubjectMaskQualityLevel: Equatable, Sendable {
    case good, warning, poor

    public var rank: Int {
        switch self {
        case .poor: 0
        case .warning: 1
        case .good: 2
        }
    }
}

public struct SubjectMaskQuality: Equatable, Sendable {
    public static let minimumReasonableCoverage: Float = 0.02
    public static let maximumReasonableCoverage: Float = 0.70
    public static let minimumUsableCoverage: Float = 0.005
    public static let maximumUsableCoverage: Float = 0.90
    public static let edgeClipMargin: CGFloat = 0.02

    public let level: SubjectMaskQualityLevel
    public let isClipped: Bool

    public init(geometry: SubjectMaskGeometry) {
        isClipped = Self.isClipped(geometry.boundingBox)
        let unusable = geometry.boundingBox == .zero
            || geometry.coverage <= Self.minimumUsableCoverage
            || geometry.coverage >= Self.maximumUsableCoverage
        if unusable {
            level = .poor
        } else {
            let clean = (Self.minimumReasonableCoverage ... Self.maximumReasonableCoverage)
                .contains(geometry.coverage) && geometry.isFresh && !isClipped
            level = clean ? .good : .warning
        }
    }

    private static func isClipped(_ rect: CGRect) -> Bool {
        guard rect != .zero else { return false }
        return rect.minX <= edgeClipMargin
            || rect.minY <= edgeClipMargin
            || rect.maxX >= 1 - edgeClipMargin
            || rect.maxY >= 1 - edgeClipMargin
    }
}
