import Foundation
import PhotoAIContracts

public struct SimilarityArtifactIndexFailure: Error, Equatable, Sendable {
    public let source: AIImageSource
    public let message: String

    public init(source: AIImageSource, message: String) {
        self.source = source
        self.message = message
    }
}

public struct SimilarityArtifactIndexResult: Sendable {
    public let artifacts: [UUID: SimilarityArtifact]
    public let failures: [SimilarityArtifactIndexFailure]
    public let usedWholeBatchFallback: Bool

    public init(
        artifacts: [UUID: SimilarityArtifact],
        failures: [SimilarityArtifactIndexFailure],
        usedWholeBatchFallback: Bool
    ) {
        self.artifacts = artifacts
        self.failures = failures
        self.usedWholeBatchFallback = usedWholeBatchFallback
    }
}

/// Bounded indexing shared by vector (CLIP) and opaque (Vision) backends.
public struct SimilarityArtifactIndexer: Sendable {
    public let primaryProvider: any ImageSimilarityArtifactProviding
    public let fallbackProvider: (any ImageSimilarityArtifactProviding)?
    public let decoder: any ImageDecoding
    public let fallbackPolicy: EmbeddingFallbackPolicy
    public let concurrencyLimit: Int

    public init(
        primaryProvider: any ImageSimilarityArtifactProviding,
        fallbackProvider: (any ImageSimilarityArtifactProviding)? = nil,
        decoder: any ImageDecoding,
        fallbackPolicy: EmbeddingFallbackPolicy = .none,
        concurrencyLimit: Int = 2
    ) {
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.decoder = decoder
        self.fallbackPolicy = fallbackPolicy
        self.concurrencyLimit = max(1, concurrencyLimit)
    }

    public func index(
        _ sources: [AIImageSource],
        progress: (@Sendable (EmbeddingIndexProgress) async -> Void)? = nil
    ) async throws -> SimilarityArtifactIndexResult {
        let firstPass = try await run(
            sources,
            provider: primaryProvider,
            perItemFallback: fallbackPolicy == .perItem ? fallbackProvider : nil,
            progress: progress
        )
        guard fallbackPolicy == .wholeBatch,
              !firstPass.failures.isEmpty,
              let fallbackProvider
        else {
            return SimilarityArtifactIndexResult(
                artifacts: firstPass.artifacts,
                failures: firstPass.failures,
                usedWholeBatchFallback: false
            )
        }

        let fallbackPass = try await run(
            sources,
            provider: fallbackProvider,
            perItemFallback: nil,
            progress: progress
        )
        return SimilarityArtifactIndexResult(
            artifacts: fallbackPass.artifacts,
            failures: fallbackPass.failures,
            usedWholeBatchFallback: true
        )
    }

    private func run(
        _ sources: [AIImageSource],
        provider: any ImageSimilarityArtifactProviding,
        perItemFallback: (any ImageSimilarityArtifactProviding)?,
        progress: (@Sendable (EmbeddingIndexProgress) async -> Void)?
    ) async throws -> (
        artifacts: [UUID: SimilarityArtifact],
        failures: [SimilarityArtifactIndexFailure]
    ) {
        guard !sources.isEmpty else { return ([:], []) }
        var artifacts: [UUID: SimilarityArtifact] = [:]
        var failures: [SimilarityArtifactIndexFailure] = []
        var nextIndex = 0
        var completed = 0

        await progress?(EmbeddingIndexProgress(
            completed: 0,
            total: sources.count,
            currentSourceID: nil
        ))
        try await withThrowingTaskGroup(of: ArtifactIndexItem.self) { group in
            func addNext() {
                guard nextIndex < sources.count else { return }
                let source = sources[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let image = try await decoder.image(for: source)
                        do {
                            return .success(
                                source,
                                try await provider.artifact(for: image, source: source)
                            )
                        } catch {
                            guard let perItemFallback else {
                                return .failure(source, String(describing: error))
                            }
                            return .success(
                                source,
                                try await perItemFallback.artifact(for: image, source: source)
                            )
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return .failure(source, String(describing: error))
                    }
                }
            }

            for _ in 0 ..< min(concurrencyLimit, sources.count) { addNext() }
            while let item = try await group.next() {
                switch item {
                case let .success(source, artifact):
                    artifacts[source.id] = artifact
                case let .failure(source, message):
                    failures.append(SimilarityArtifactIndexFailure(
                        source: source,
                        message: message
                    ))
                }
                completed += 1
                await progress?(EmbeddingIndexProgress(
                    completed: completed,
                    total: sources.count,
                    currentSourceID: item.source.id
                ))
                addNext()
            }
        }
        return (artifacts, failures)
    }
}

private enum ArtifactIndexItem: Sendable {
    case success(AIImageSource, SimilarityArtifact)
    case failure(AIImageSource, String)

    var source: AIImageSource {
        switch self {
        case let .success(source, _), let .failure(source, _): source
        }
    }
}
