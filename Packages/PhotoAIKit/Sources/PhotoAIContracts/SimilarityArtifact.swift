import CoreGraphics
import Foundation

public struct SourceFingerprint: Codable, Hashable, Sendable {
    public let standardizedPath: String
    public let fileSize: Int64?
    public let modificationDate: Date?

    public init(
        standardizedPath: String,
        fileSize: Int64?,
        modificationDate: Date?
    ) {
        self.standardizedPath = standardizedPath
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    public init(source: AIImageSource) {
        let identity = SourceFileIdentity.read(from: source.url)
        self.init(
            standardizedPath: source.url.standardizedFileURL.path,
            fileSize: identity.fileSize,
            modificationDate: identity.modificationDate
        )
    }
}

public struct SimilarityBackendDescriptor: Codable, Hashable, Sendable {
    public let backend: String
    public let modelFingerprint: String
    public let representation: String
    public let preprocessingVersion: String
    public let normalizationVersion: String
    public let configurationVersion: String

    public init(
        backend: String,
        modelFingerprint: String,
        representation: String,
        preprocessingVersion: String,
        normalizationVersion: String,
        configurationVersion: String
    ) {
        self.backend = backend
        self.modelFingerprint = modelFingerprint
        self.representation = representation
        self.preprocessingVersion = preprocessingVersion
        self.normalizationVersion = normalizationVersion
        self.configurationVersion = configurationVersion
    }
}

/// Complete identity for a persisted similarity artifact.
public struct SimilarityArtifactDescriptor: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2

    public let backend: String
    public let modelFingerprint: String
    public let dimensions: Int?
    public let representation: String
    public let preprocessingVersion: String
    public let normalizationVersion: String
    public let configurationVersion: String
    public let sourceFingerprint: SourceFingerprint
    public let schemaVersion: Int

    public init(
        backend: String,
        modelFingerprint: String,
        dimensions: Int?,
        representation: String,
        preprocessingVersion: String,
        normalizationVersion: String,
        configurationVersion: String,
        sourceFingerprint: SourceFingerprint,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.backend = backend
        self.modelFingerprint = modelFingerprint
        self.dimensions = dimensions
        self.representation = representation
        self.preprocessingVersion = preprocessingVersion
        self.normalizationVersion = normalizationVersion
        self.configurationVersion = configurationVersion
        self.sourceFingerprint = sourceFingerprint
        self.schemaVersion = schemaVersion
    }

    public init(
        backend: SimilarityBackendDescriptor,
        dimensions: Int?,
        sourceFingerprint: SourceFingerprint,
        schemaVersion: Int = Self.currentSchemaVersion
    ) {
        self.init(
            backend: backend.backend,
            modelFingerprint: backend.modelFingerprint,
            dimensions: dimensions,
            representation: backend.representation,
            preprocessingVersion: backend.preprocessingVersion,
            normalizationVersion: backend.normalizationVersion,
            configurationVersion: backend.configurationVersion,
            sourceFingerprint: sourceFingerprint,
            schemaVersion: schemaVersion
        )
    }

    /// Compatibility for distance calculations deliberately excludes the
    /// source fingerprint while requiring every backend/configuration field.
    public func isCompatibleForDistance(with other: Self) -> Bool {
        backend == other.backend
            && modelFingerprint == other.modelFingerprint
            && dimensions == other.dimensions
            && representation == other.representation
            && preprocessingVersion == other.preprocessingVersion
            && normalizationVersion == other.normalizationVersion
            && configurationVersion == other.configurationVersion
            && schemaVersion == other.schemaVersion
    }
}

/// Backend-owned payload plus enough identity to reject stale or incompatible
/// artifacts without interpreting that payload in the host application.
public struct SimilarityArtifact: Codable, Equatable, Sendable {
    public let descriptor: SimilarityArtifactDescriptor
    public let payload: Data

    public init(descriptor: SimilarityArtifactDescriptor, payload: Data) {
        self.descriptor = descriptor
        self.payload = payload
    }
}

public typealias EmbeddingArtifactDescriptor = SimilarityArtifactDescriptor

public struct EmbeddingArtifact: Codable, Equatable, Sendable {
    public let descriptor: EmbeddingArtifactDescriptor
    public let embedding: ImageEmbedding

    public init(
        descriptor: EmbeddingArtifactDescriptor,
        embedding: ImageEmbedding
    ) {
        self.descriptor = descriptor
        self.embedding = embedding
    }

    public var isInternallyConsistent: Bool {
        descriptor.backend == embedding.backend
            && descriptor.modelFingerprint == embedding.modelIdentity.artifactIdentifier
            && descriptor.dimensions == embedding.values.count
            && !embedding.values.isEmpty
    }
}

public protocol ImageSimilarityArtifactProviding: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    func artifact(
        for image: CGImage,
        source: AIImageSource
    ) async throws -> SimilarityArtifact
}

public protocol ImageSimilarityArtifactComparing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact
    ) throws -> Float?
}

public typealias ImageSimilarityBackend =
    ImageSimilarityArtifactProviding & ImageSimilarityArtifactComparing
