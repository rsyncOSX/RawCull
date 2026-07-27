import Foundation
import PhotoAIContracts

public enum EmbeddingFallbackPolicy: Sendable {
    case none
    case perItem
    case wholeBatch
}

public struct EmbeddingIndexFailure: Error, Equatable, Sendable {
    public let source: AIImageSource
    public let message: String

    public init(source: AIImageSource, message: String) {
        self.source = source
        self.message = message
    }
}

public struct EmbeddingIndexProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentSourceID: UUID?

    public init(completed: Int, total: Int, currentSourceID: UUID?) {
        self.completed = completed
        self.total = total
        self.currentSourceID = currentSourceID
    }
}

public struct EmbeddingIndexResult: Sendable {
    public let embeddings: [UUID: ImageEmbedding]
    public let failures: [EmbeddingIndexFailure]
    public let usedWholeBatchFallback: Bool

    public init(
        embeddings: [UUID: ImageEmbedding],
        failures: [EmbeddingIndexFailure],
        usedWholeBatchFallback: Bool
    ) {
        self.embeddings = embeddings
        self.failures = failures
        self.usedWholeBatchFallback = usedWholeBatchFallback
    }
}

/// Bounded, UI-independent indexing with explicit fallback policy.
public struct EmbeddingIndexer: Sendable {
    public let primaryProvider: any ImageEmbeddingProviding
    public let fallbackProvider: (any ImageEmbeddingProviding)?
    public let decoder: any ImageDecoding
    public let fallbackPolicy: EmbeddingFallbackPolicy
    public let concurrencyLimit: Int

    public init(
        primaryProvider: any ImageEmbeddingProviding,
        fallbackProvider: (any ImageEmbeddingProviding)? = nil,
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
    ) async throws -> EmbeddingIndexResult {
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
            return EmbeddingIndexResult(
                embeddings: firstPass.embeddings,
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
        return EmbeddingIndexResult(
            embeddings: fallbackPass.embeddings,
            failures: fallbackPass.failures,
            usedWholeBatchFallback: true
        )
    }

    private func run(
        _ sources: [AIImageSource],
        provider: any ImageEmbeddingProviding,
        perItemFallback: (any ImageEmbeddingProviding)?,
        progress: (@Sendable (EmbeddingIndexProgress) async -> Void)?
    ) async throws -> (embeddings: [UUID: ImageEmbedding], failures: [EmbeddingIndexFailure]) {
        guard !sources.isEmpty else { return ([:], []) }
        var embeddings: [UUID: ImageEmbedding] = [:]
        var failures: [EmbeddingIndexFailure] = []
        var nextIndex = 0
        var completed = 0

        await progress?(EmbeddingIndexProgress(completed: 0, total: sources.count, currentSourceID: nil))
        try await withThrowingTaskGroup(of: IndexItem.self) { group in
            func addNext() {
                guard nextIndex < sources.count else { return }
                let source = sources[nextIndex]
                nextIndex += 1
                group.addTask {
                    try Task.checkCancellation()
                    do {
                        let image = try await decoder.image(for: source)
                        do {
                            return .success(source, try await provider.embedding(for: image))
                        } catch {
                            guard let perItemFallback else {
                                return .failure(source, String(describing: error))
                            }
                            return .success(source, try await perItemFallback.embedding(for: image))
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
                case let .success(source, embedding):
                    embeddings[source.id] = embedding
                case let .failure(source, message):
                    failures.append(EmbeddingIndexFailure(source: source, message: message))
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
        return (embeddings, failures)
    }
}

private enum IndexItem: Sendable {
    case success(AIImageSource, ImageEmbedding)
    case failure(AIImageSource, String)

    var source: AIImageSource {
        switch self {
        case let .success(source, _), let .failure(source, _): source
        }
    }
}
