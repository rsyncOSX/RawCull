import Foundation
import PhotoAIContracts

/// Reads and writes the source application's version-1 CLIP envelope for a staged migration.
public enum LegacyCLIPEmbeddingCodec {
    @available(*, deprecated, message: "Legacy envelopes discard model and source identity. Use EmbeddingCodec.encode(EmbeddingArtifact) for new data.")
    public static func encode(_ embedding: ImageEmbedding) throws -> Data {
        try JSONEncoder().encode(Envelope(
            version: 1,
            backend: "clip",
            dimensions: embedding.values.count,
            values: ImageEmbedding.normalized(embedding.values)
        ))
    }

    public static func decode(
        _ data: Data,
        modelIdentity: ModelIdentity
    ) -> ImageEmbedding? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.version == 1,
              envelope.backend == "clip",
              envelope.dimensions == envelope.values.count,
              !envelope.values.isEmpty
        else { return nil }
        return ImageEmbedding(
            backend: "clip",
            modelIdentity: modelIdentity,
            values: envelope.values
        )
    }

    private struct Envelope: Codable {
        let version: Int
        let backend: String
        let dimensions: Int
        let values: [Float]
    }
}
