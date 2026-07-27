import Foundation
import PhotoAIContracts

/// Immutable cache configuration shared by mask readers and segmentation workflows.
public struct SubjectMaskRepositoryConfiguration: Equatable, Sendable {
    public let defaultPrompt: SubjectSegmentationPrompt
    public let modelIdentity: ModelIdentity
    public let inputMaxSide: Int

    public init(
        defaultPrompt: SubjectSegmentationPrompt = .subject,
        modelIdentity: ModelIdentity,
        inputMaxSide: Int = 4_320
    ) {
        self.defaultPrompt = defaultPrompt
        self.modelIdentity = modelIdentity
        self.inputMaxSide = inputMaxSide
    }
}

/// Injected cache facade for consumers that need masks without invoking inference.
/// It replaces host-level static readers and keeps prompt/model/size configuration explicit.
public struct SubjectMaskRepository: SubjectMaskProviding, Sendable {
    public let configuration: SubjectMaskRepositoryConfiguration
    private let stores: [any SubjectMaskStoring]

    public init(
        configuration: SubjectMaskRepositoryConfiguration,
        stores: [any SubjectMaskStoring]
    ) {
        self.configuration = configuration
        self.stores = stores
    }

    public func cachedMask(for source: AIImageSource) async -> SubjectSegmentationResult? {
        await cachedMask(for: source, prompt: configuration.defaultPrompt)
    }

    public func cachedMask(
        for source: AIImageSource,
        prompt: SubjectSegmentationPrompt
    ) async -> SubjectSegmentationResult? {
        let key = await storageKey(for: source, prompt: prompt)
        for store in stores {
            if let result = await store.load(for: key) {
                return result
            }
        }
        return nil
    }

    public func contains(
        _ source: AIImageSource,
        prompt: SubjectSegmentationPrompt? = nil
    ) async -> Bool {
        let key = await storageKey(
            for: source,
            prompt: prompt ?? configuration.defaultPrompt
        )
        for store in stores where await store.contains(key) {
            return true
        }
        return false
    }

    public func storageKey(
        for source: AIImageSource,
        prompt: SubjectSegmentationPrompt? = nil
    ) async -> SubjectMaskStorageKey {
        let identity = await Task { @concurrent in
            SourceFileIdentity.read(from: source.url)
        }.value
        return SubjectMaskStorageKey(
            source: source,
            sourceIdentity: identity,
            prompt: prompt ?? configuration.defaultPrompt,
            modelIdentity: configuration.modelIdentity,
            inputMaxSide: configuration.inputMaxSide
        )
    }
}
