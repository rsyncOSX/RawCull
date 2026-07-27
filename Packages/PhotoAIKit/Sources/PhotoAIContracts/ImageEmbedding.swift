import CoreGraphics
import Foundation

public struct ImageEmbedding: Codable, Equatable, Sendable {
    public let backend: String
    public let modelIdentity: ModelIdentity
    public let values: [Float]

    public init(
        backend: String,
        modelIdentity: ModelIdentity,
        values: [Float],
        normalize: Bool = true
    ) {
        self.backend = backend
        self.modelIdentity = modelIdentity
        self.values = normalize ? Self.normalized(values) : values
    }

    public static func normalized(_ values: [Float]) -> [Float] {
        let magnitude = sqrt(values.reduce(Float.zero) { $0 + $1 * $1 })
        guard magnitude.isFinite, magnitude > 0 else { return values }
        return values.map { $0 / magnitude }
    }

    public func cosineDistance(to other: ImageEmbedding) -> Float? {
        guard backend == other.backend,
              modelIdentity == other.modelIdentity,
              values.count == other.values.count,
              !values.isEmpty
        else { return nil }
        let dot = zip(values, other.values).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let leftMagnitude = sqrt(values.reduce(Float.zero) { $0 + $1 * $1 })
        let rightMagnitude = sqrt(other.values.reduce(Float.zero) { $0 + $1 * $1 })
        guard leftMagnitude > 0, rightMagnitude > 0 else { return nil }
        let distance = 1 - dot / (leftMagnitude * rightMagnitude)
        guard distance.isFinite else { return nil }
        return max(0, min(2, distance))
    }
}

public protocol ImageEmbeddingProviding: Sendable {
    var modelIdentity: ModelIdentity { get }
    func embedding(for image: CGImage) async throws -> ImageEmbedding
}

public protocol ImageDecoding: Sendable {
    func image(for source: AIImageSource) async throws -> CGImage
}
