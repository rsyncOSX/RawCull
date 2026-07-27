import Foundation
import PhotoAIContracts

public enum SimilarityMetric {
    public static func cosineDistance(
        _ left: ImageEmbedding,
        _ right: ImageEmbedding
    ) -> Float? {
        left.cosineDistance(to: right)
    }

    public static func ranked(
        anchor: ImageEmbedding,
        candidates: [UUID: ImageEmbedding]
    ) -> [(id: UUID, distance: Float)] {
        candidates.compactMap { id, candidate in
            anchor.cosineDistance(to: candidate).map { (id, $0) }
        }.sorted { $0.distance < $1.distance }
    }
}
