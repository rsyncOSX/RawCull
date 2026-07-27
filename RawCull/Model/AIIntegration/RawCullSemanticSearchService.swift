import Foundation
import PhotoAIContracts

/// A catalog entry paired with an already-persisted CLIP image artifact.
///
/// The catalog order is captured before asynchronous work starts and provides
/// the deterministic tie-breaker for equal semantic scores.
nonisolated struct RawCullSemanticSearchCandidate: Sendable {
    let fileID: UUID
    let fileName: String
    let catalogOrder: Int
    let artifact: SimilarityArtifact
}

/// A relative semantic match. CLIP cosine similarity is not a confidence
/// value; larger scores only mean that one result is closer to the query than
/// another result from the same search.
nonisolated struct RawCullSemanticSearchMatch: Equatable, Identifiable, Sendable {
    let fileID: UUID
    let score: Float

    var id: UUID { fileID }
}

nonisolated struct RawCullSemanticSearchArtifactFailure: Equatable, Sendable {
    let fileID: UUID
    let message: String
}

nonisolated struct RawCullSemanticSearchOutput: Equatable, Sendable {
    let query: String
    let matches: [RawCullSemanticSearchMatch]
    let compatibleArtifactCount: Int
    let incompatibleArtifactCount: Int
    let failures: [RawCullSemanticSearchArtifactFailure]
}

nonisolated enum RawCullSemanticSearchError: Error, Equatable, Sendable {
    case emptyQuery
    case noCompatibleArtifacts
    case incompatibleProviderDescriptors
    case incompatibleTextEmbedding
    case providerFailure(String)
}

/// Narrow RawCull boundary for query encoding plus cached-artifact ranking.
///
/// Implementations must not decode source images or generate image artifacts.
/// Query embeddings are intentionally scoped to one call and are not persisted.
nonisolated protocol RawCullSemanticSearchServicing: Sendable {
    var backendDescriptor: SimilarityBackendDescriptor { get }
    var promptPolicyVersion: String { get }

    func rank(
        query: String,
        candidates: [RawCullSemanticSearchCandidate],
    ) async throws -> RawCullSemanticSearchOutput
}

/// Literal-query CLIP semantic search backed by PhotoAIKit.
///
/// PhotoAIKit owns text tokenization, inference, artifact compatibility, and
/// primitive cosine similarity. RawCull owns catalog admission, cancellation,
/// failure isolation, and deterministic ranking.
nonisolated struct RawCullCLIPSemanticSearchService: RawCullSemanticSearchServicing {
    static let literalPromptPolicyVersion = "literal-v1"

    let backendDescriptor: SimilarityBackendDescriptor
    let promptPolicyVersion = Self.literalPromptPolicyVersion

    private let textProvider: any TextEmbeddingProviding
    private let comparator: any ImageTextSimilarityComparing

    init(backend: any ImageTextSimilarityBackend) {
        self.init(textProvider: backend, comparator: backend)
    }

    init(
        textProvider: any TextEmbeddingProviding,
        comparator: any ImageTextSimilarityComparing,
    ) {
        self.textProvider = textProvider
        self.comparator = comparator
        self.backendDescriptor = textProvider.backendDescriptor
    }

    @concurrent
    func rank(
        query: String,
        candidates: [RawCullSemanticSearchCandidate],
    ) async throws -> RawCullSemanticSearchOutput {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw RawCullSemanticSearchError.emptyQuery
        }
        guard comparator.backendDescriptor == backendDescriptor else {
            throw RawCullSemanticSearchError.incompatibleProviderDescriptors
        }

        let compatibleCandidates = candidates.filter {
            Self.isCompatibleDescriptor(
                $0.artifact.descriptor,
                backend: backendDescriptor,
            )
        }
        guard !compatibleCandidates.isEmpty else {
            throw RawCullSemanticSearchError.noCompatibleArtifacts
        }

        try Task.checkCancellation()
        let textEmbedding: TextEmbedding
        do {
            textEmbedding = try await textProvider.embedding(for: trimmedQuery)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw RawCullSemanticSearchError.providerFailure(
                String(describing: error),
            )
        }
        try Task.checkCancellation()

        guard textEmbedding.descriptor.backend == backendDescriptor else {
            throw RawCullSemanticSearchError.incompatibleTextEmbedding
        }

        var ranked: [(
            match: RawCullSemanticSearchMatch,
            fileName: String,
            catalogOrder: Int
        )] = []
        var failures: [RawCullSemanticSearchArtifactFailure] = []
        ranked.reserveCapacity(compatibleCandidates.count)

        for (offset, candidate) in compatibleCandidates.enumerated() {
            if offset & 0x3F == 0 {
                try Task.checkCancellation()
            }
            do {
                let score = try comparator.similarity(
                    image: candidate.artifact,
                    text: textEmbedding,
                )
                guard score.isFinite, (-1 ... 1).contains(score) else {
                    failures.append(
                        RawCullSemanticSearchArtifactFailure(
                            fileID: candidate.fileID,
                            message: "PhotoAIKit returned an invalid cosine similarity.",
                        ),
                    )
                    continue
                }
                ranked.append(
                    (
                        RawCullSemanticSearchMatch(
                            fileID: candidate.fileID,
                            score: score,
                        ),
                        candidate.fileName,
                        candidate.catalogOrder
                    ),
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(
                    RawCullSemanticSearchArtifactFailure(
                        fileID: candidate.fileID,
                        message: String(describing: error),
                    ),
                )
            }
        }

        try Task.checkCancellation()
        ranked.sort { lhs, rhs in
            if lhs.match.score != rhs.match.score {
                return lhs.match.score > rhs.match.score
            }
            if lhs.catalogOrder != rhs.catalogOrder {
                return lhs.catalogOrder < rhs.catalogOrder
            }
            let nameOrdering = lhs.fileName.localizedStandardCompare(rhs.fileName)
            if nameOrdering != .orderedSame {
                return nameOrdering == .orderedAscending
            }
            return lhs.match.fileID.uuidString < rhs.match.fileID.uuidString
        }

        return RawCullSemanticSearchOutput(
            query: trimmedQuery,
            matches: ranked.map(\.match),
            compatibleArtifactCount: compatibleCandidates.count,
            incompatibleArtifactCount: candidates.count - compatibleCandidates.count,
            failures: failures,
        )
    }

    private static func isCompatibleDescriptor(
        _ descriptor: SimilarityArtifactDescriptor,
        backend: SimilarityBackendDescriptor,
    ) -> Bool {
        descriptor.schemaVersion == SimilarityArtifactDescriptor.currentSchemaVersion
            && descriptor.backend == backend.backend
            && descriptor.modelFingerprint == backend.modelFingerprint
            && descriptor.representation == backend.representation
            && descriptor.preprocessingVersion == backend.preprocessingVersion
            && descriptor.normalizationVersion == backend.normalizationVersion
            && descriptor.configurationVersion == backend.configurationVersion
    }
}
