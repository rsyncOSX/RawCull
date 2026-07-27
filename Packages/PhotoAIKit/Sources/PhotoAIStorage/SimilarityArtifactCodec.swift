import Foundation
import PhotoAIContracts

public enum SimilarityArtifactCodec {
    public static let currentVersion = 1

    public static func encode(_ artifact: SimilarityArtifact) throws -> Data {
        try JSONEncoder().encode(Envelope(
            version: currentVersion,
            artifact: artifact
        ))
    }

    public static func decode(_ data: Data) throws -> SimilarityArtifact {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == currentVersion else {
            throw SimilarityArtifactCodecError.unsupportedVersion(envelope.version)
        }
        guard envelope.artifact.descriptor.schemaVersion
            == SimilarityArtifactDescriptor.currentSchemaVersion
        else {
            throw SimilarityArtifactCodecError.unsupportedDescriptorSchema(
                envelope.artifact.descriptor.schemaVersion
            )
        }
        return envelope.artifact
    }

    private struct Envelope: Codable {
        let version: Int
        let artifact: SimilarityArtifact
    }
}

public enum SimilarityArtifactCodecError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case unsupportedDescriptorSchema(Int)
}
