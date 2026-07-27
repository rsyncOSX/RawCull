import Foundation

public struct SubjectMaskStorageKey: Codable, Hashable, Sendable {
    public let source: AIImageSource
    public let sourceIdentity: SourceFileIdentity
    public let prompt: SubjectSegmentationPrompt
    public let modelIdentity: ModelIdentity
    public let inputMaxSide: Int

    public init(
        source: AIImageSource,
        sourceIdentity: SourceFileIdentity,
        prompt: SubjectSegmentationPrompt,
        modelIdentity: ModelIdentity,
        inputMaxSide: Int
    ) {
        self.source = source
        self.sourceIdentity = sourceIdentity
        self.prompt = prompt
        self.modelIdentity = modelIdentity
        self.inputMaxSide = inputMaxSide
    }
}

public protocol SubjectMaskStoring: Sendable {
    func load(for key: SubjectMaskStorageKey) async -> SubjectSegmentationResult?
    func contains(_ key: SubjectMaskStorageKey) async -> Bool
    func save(_ result: SubjectSegmentationResult, for key: SubjectMaskStorageKey) async throws
}

public struct SubjectMaskCacheMetadata: Equatable, Sendable {
    public let modificationDate: Date?

    public init(modificationDate: Date?) {
        self.modificationDate = modificationDate
    }
}

/// Optional cache-inspection capability used by catalog workflows. Stores that
/// do not persist metadata do not need to conform.
public protocol SubjectMaskCacheMetadataProviding: Sendable {
    func cacheMetadata(for key: SubjectMaskStorageKey) async -> SubjectMaskCacheMetadata?
}

/// Cache-only mask access for host presentation and analysis layers.
/// Implementations own cache configuration; callers supply only package-owned sources.
public protocol SubjectMaskProviding: Sendable {
    func cachedMask(
        for source: AIImageSource,
        prompt: SubjectSegmentationPrompt
    ) async -> SubjectSegmentationResult?
}

public struct SubjectMaskPrefetchProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let cached: Int
    public let generated: Int
    public let failed: Int
    public let currentSourceID: UUID?

    public init(
        completed: Int,
        total: Int,
        cached: Int,
        generated: Int,
        failed: Int,
        currentSourceID: UUID?
    ) {
        self.completed = completed
        self.total = total
        self.cached = cached
        self.generated = generated
        self.failed = failed
        self.currentSourceID = currentSourceID
    }

    public var remaining: Int { max(0, total - completed) }
}
