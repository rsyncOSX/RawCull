import Foundation
import PhotoAIContracts

/// Typed persistence for embeddings. Host applications choose where the data is stored.
public enum EmbeddingCodec {
    public static let currentSchemaVersion = 2

    @available(*, deprecated, message: "Encode EmbeddingArtifact so model, source, preprocessing, and normalization identity are preserved.")
    public static func encode(_ embedding: ImageEmbedding) throws -> Data {
        try JSONEncoder().encode(Envelope(version: 1, embedding: embedding))
    }

    public static func encode(_ artifact: EmbeddingArtifact) throws -> Data {
        guard artifact.isInternallyConsistent,
              artifact.descriptor.schemaVersion == currentSchemaVersion
        else { throw EmbeddingCodecError.inconsistentArtifact }
        return try JSONEncoder().encode(ArtifactEnvelope(
            version: currentSchemaVersion,
            artifact: artifact
        ))
    }

    public static func decode(_ data: Data) throws -> ImageEmbedding {
        try JSONDecoder().decode(Envelope.self, from: data).embedding
    }

    public static func decodeArtifact(_ data: Data) throws -> EmbeddingArtifact {
        let envelope = try JSONDecoder().decode(ArtifactEnvelope.self, from: data)
        guard envelope.version == currentSchemaVersion,
              envelope.artifact.descriptor.schemaVersion == currentSchemaVersion,
              envelope.artifact.isInternallyConsistent
        else { throw EmbeddingCodecError.inconsistentArtifact }
        return envelope.artifact
    }

    /// Reads the current format and both previous CLIP formats. Legacy values
    /// are accepted only against the caller's real current identity and are
    /// returned as a fully described artifact ready to rewrite with `encode`.
    public static func decodeMigrating(
        _ data: Data,
        expectedDescriptor: EmbeddingArtifactDescriptor,
        currentModelIdentity: ModelIdentity
    ) throws -> EmbeddingMigrationResult {
        if let artifact = try? decodeArtifact(data) {
            guard artifact.descriptor == expectedDescriptor else {
                throw EmbeddingCodecError.descriptorMismatch
            }
            return EmbeddingMigrationResult(
                artifact: artifact,
                sourceFormat: .current,
                requiresRewrite: false
            )
        }

        let embedding: ImageEmbedding
        let sourceFormat: EmbeddingMigrationResult.SourceFormat
        if let typed = try? decode(data) {
            embedding = typed
            sourceFormat = .typedVersion1
        } else if let legacy = LegacyCLIPEmbeddingCodec.decode(
            data,
            modelIdentity: currentModelIdentity
        ) {
            embedding = legacy
            sourceFormat = .rawCullCLIPVersion1
        } else {
            throw EmbeddingCodecError.unrecognizedFormat
        }

        guard expectedDescriptor.backend == embedding.backend,
              expectedDescriptor.modelFingerprint == currentModelIdentity.artifactIdentifier,
              expectedDescriptor.dimensions == embedding.values.count,
              embedding.modelIdentity.cacheIdentifier == currentModelIdentity.cacheIdentifier
        else { throw EmbeddingCodecError.descriptorMismatch }

        let migratedEmbedding = ImageEmbedding(
            backend: embedding.backend,
            modelIdentity: currentModelIdentity,
            values: embedding.values
        )

        return EmbeddingMigrationResult(
            artifact: EmbeddingArtifact(
                descriptor: expectedDescriptor,
                embedding: migratedEmbedding
            ),
            sourceFormat: sourceFormat,
            requiresRewrite: true
        )
    }

    private struct Envelope: Codable {
        let version: Int
        let embedding: ImageEmbedding
    }

    private struct ArtifactEnvelope: Codable {
        let version: Int
        let artifact: EmbeddingArtifact
    }
}

public struct EmbeddingMigrationResult: Equatable, Sendable {
    public enum SourceFormat: Equatable, Sendable {
        case current
        case typedVersion1
        case rawCullCLIPVersion1
    }

    public let artifact: EmbeddingArtifact
    public let sourceFormat: SourceFormat
    public let requiresRewrite: Bool

    public init(
        artifact: EmbeddingArtifact,
        sourceFormat: SourceFormat,
        requiresRewrite: Bool
    ) {
        self.artifact = artifact
        self.sourceFormat = sourceFormat
        self.requiresRewrite = requiresRewrite
    }
}

public enum EmbeddingCodecError: Error, Equatable, Sendable {
    case inconsistentArtifact
    case descriptorMismatch
    case unrecognizedFormat
}
