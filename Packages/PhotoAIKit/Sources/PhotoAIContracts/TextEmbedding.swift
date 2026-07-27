import Foundation

/// Complete identity for a query-scoped text embedding.
///
/// Text embeddings are deliberately not file-backed similarity artifacts.
/// They retain the complete image-backend identity so image/text comparison
/// can reject any incompatible model or pipeline configuration.
public struct TextEmbeddingDescriptor: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public let backend: SimilarityBackendDescriptor
    public let dimensions: Int
    public let tokenizerVersion: String
    public let schemaVersion: Int

    public init(
        backend: SimilarityBackendDescriptor,
        dimensions: Int,
        tokenizerVersion: String,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.backend = backend
        self.dimensions = dimensions
        self.tokenizerVersion = tokenizerVersion
        self.schemaVersion = schemaVersion
    }
}

/// A normalized text vector in the same embedding space as compatible image
/// artifacts.
public struct TextEmbedding: Codable, Equatable, Sendable {
    /// Tolerance used when validating the model's documented L2-normalized
    /// output. PhotoAIKit does not normalize this value a second time.
    public static let normalizationTolerance: Float = 0.001

    public let descriptor: TextEmbeddingDescriptor
    public let values: [Float]

    public init(
        descriptor: TextEmbeddingDescriptor,
        values: [Float]
    ) throws {
        try Self.validate(descriptor: descriptor, values: values)
        self.descriptor = descriptor
        self.values = values
    }

    public func validated() throws -> Self {
        try Self.validate(descriptor: descriptor, values: values)
        return self
    }

    private enum CodingKeys: String, CodingKey {
        case descriptor
        case values
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            descriptor: container.decode(TextEmbeddingDescriptor.self, forKey: .descriptor),
            values: container.decode([Float].self, forKey: .values)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(descriptor, forKey: .descriptor)
        try container.encode(values, forKey: .values)
    }

    private static func validate(
        descriptor: TextEmbeddingDescriptor,
        values: [Float]
    ) throws {
        guard descriptor.schemaVersion == TextEmbeddingDescriptor.currentSchemaVersion else {
            throw TextEmbeddingValidationError.unsupportedSchemaVersion(
                descriptor.schemaVersion
            )
        }
        guard descriptor.dimensions > 0 else {
            throw TextEmbeddingValidationError.invalidDimensions(descriptor.dimensions)
        }
        guard values.count == descriptor.dimensions else {
            throw TextEmbeddingValidationError.dimensionMismatch(
                expected: descriptor.dimensions,
                actual: values.count
            )
        }
        guard let invalidIndex = values.firstIndex(where: { !$0.isFinite }) else {
            let squaredMagnitude = values.reduce(Float.zero) { $0 + $1 * $1 }
            guard squaredMagnitude.isFinite, squaredMagnitude > 0 else {
                throw TextEmbeddingValidationError.zeroNorm
            }
            let magnitude = sqrt(squaredMagnitude)
            guard abs(magnitude - 1) <= normalizationTolerance else {
                throw TextEmbeddingValidationError.notNormalized(magnitude: magnitude)
            }
            return
        }
        throw TextEmbeddingValidationError.nonFiniteValue(index: invalidIndex)
    }
}

public enum TextEmbeddingValidationError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidDimensions(Int)
    case dimensionMismatch(expected: Int, actual: Int)
    case nonFiniteValue(index: Int)
    case zeroNorm
    case notNormalized(magnitude: Float)
}

public protocol TextEmbeddingProviding: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    func embedding(for text: String) async throws -> TextEmbedding
}

/// Compares a file-backed image artifact with a query-scoped text embedding.
///
/// The result is cosine similarity in `-1 ... 1`; larger values indicate a
/// closer semantic match.
public protocol ImageTextSimilarityComparing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    func similarity(
        image: SimilarityArtifact,
        text: TextEmbedding
    ) throws -> Float
}

public typealias ImageTextSimilarityBackend =
    TextEmbeddingProviding & ImageTextSimilarityComparing

public enum ImageTextSimilarityError: Error, Equatable, Sendable {
    case unsupportedImageBackend(expected: String, actual: String)
    case unsupportedTextBackend(expected: String, actual: String)
    case incompatibleModelFingerprint
    case incompatibleDimensions(expected: Int, actual: Int?)
    case incompatibleRepresentation
    case incompatiblePreprocessing
    case incompatibleNormalization
    case incompatibleConfiguration
    case incompatibleTokenizer
    case invalidImageSchemaVersion(Int)
    case invalidTextEmbedding(TextEmbeddingValidationError)
    case invalidImagePayload(String)
}
