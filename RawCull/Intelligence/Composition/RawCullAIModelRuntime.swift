import CoreAICLIPBackend
import CoreAISAM3Backend
import CoreGraphics
import Foundation
import OSLog
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
import VisionFeaturePrintBackend

/// Application-owned runtime for RawCull's AI model backends and resources.
///
/// `RawCullApplicationState` constructs stateful features and binds them to the
/// services they need. Views and `RawCullViewModel` do not traverse this object.
/// The container is main-actor isolated for configuration, while CLIP, SAM 3,
/// and Qwen retain independent actor isolation for resource and inference work.
@MainActor
final class RawCullAIModelRuntime {
    let paths: RawCullAIPaths
    let qwenInference: any QwenInferenceServing
    private let sam3ModelResourceManager: RawCullAIModelResourceManager<CoreAISAM3Provider>
    private let clipDataCompModelResourceManager:
        RawCullAIModelResourceManager<CoreAICLIPProvider>
    private let clipOpenAIModelResourceManager:
        RawCullAIModelResourceManager<CoreAICLIPProvider>
    let visionSimilarityProvider: VisionFeaturePrintBackend
    let visionSimilarityService: any RawCullSimilarityServicing
    private(set) var clipSimilarityProviders: [
        RawCullCLIPModel: CoreAICLIPProvider
    ]
    private(set) var clipSimilarityModelLocations: [RawCullCLIPModel: URL]

    let subjectMaskMemoryStore: SubjectMaskMemoryStore
    let subjectMaskDiskStore: SubjectMaskDiskStore?
    let objectMaskMemoryStore: ObjectMaskMemoryStore
    let objectMaskDiskStore: ObjectMaskDiskStore?
    private(set) var objectSegmentation: ObjectSegmentationService?
    private(set) var subjectMaskRepository: SubjectMaskRepository
    private(set) var sam3Configuration: SubjectMaskRepositoryConfiguration
    private(set) var sam3Segmentation: SegmentationService
    private(set) var subjectMaskSelector: SubjectMaskSelector
    private let subjectMaskStorageCapability: RawCullAICapabilityStatus
    private let subjectMaskStores: [any SubjectMaskStoring]
    private let defaultPrompt: SubjectSegmentationPrompt
    private let inputMaxSide: Int
    private weak var deepAIReviewFeature: DeepAIReviewFeature?
    private var selectedSegmentationModel: RawCullSegmentationModel = .defaultSelection
    private var segmentationProviders: [RawCullSegmentationModel: any SubjectSegmenting] = [:]
    private var activeSegmentationModelIdentity: ModelIdentity?
    private var capabilitySnapshot: RawCullAICapabilities

    init(
        paths: RawCullAIPaths = .live(),
        defaultPrompt: SubjectSegmentationPrompt = .subject,
        inputMaxSide: Int = 4320,
        qwenInference: any QwenInferenceServing = QwenInferenceRuntime(),
    ) {
        self.paths = paths
        self.qwenInference = qwenInference
        let sam3CandidateURLs: [URL] = []
        let defaultSegmentationCandidateURLs: [URL] = []
        let clipDataCompCandidateURLs: [URL] = []
        let clipOpenAICandidateURLs: [URL] = []
        self.sam3ModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: sam3CandidateURLs,
            factory: CoreAISAM3Provider.factory,
        )
        self.clipDataCompModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: clipDataCompCandidateURLs,
            factory: CoreAICLIPProvider.factory,
        )
        self.clipOpenAIModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: clipOpenAICandidateURLs,
            factory: CoreAICLIPProvider.factory,
        )
        self.clipSimilarityProviders = [:]
        self.clipSimilarityModelLocations = [:]

        let visionProvider = VisionFeaturePrintBackend()
        self.visionSimilarityProvider = visionProvider
        self.visionSimilarityService = RawCullVisionSimilarityService(
            backend: visionProvider,
        )

        let memoryStore = SubjectMaskMemoryStore()
        self.subjectMaskMemoryStore = memoryStore

        let diskStoreResult = Self.makeSubjectMaskDiskStore(at: paths.subjectMaskDirectory)
        self.subjectMaskDiskStore = diskStoreResult.store
        self.subjectMaskStorageCapability = diskStoreResult.capability

        self.objectMaskMemoryStore = ObjectMaskMemoryStore()
        self.objectMaskDiskStore = try? ObjectMaskDiskStore(
            cacheDirectory: paths.objectMaskDirectory,
        )
        self.objectSegmentation = nil

        var stores: [any SubjectMaskStoring] = [memoryStore]
        if let diskStore = diskStoreResult.store {
            stores.append(diskStore)
        }
        self.subjectMaskStores = stores
        self.defaultPrompt = defaultPrompt
        self.inputMaxSide = inputMaxSide

        let sam3Provider = UnavailableSegmentationProvider()
        let configuration = SubjectMaskRepositoryConfiguration(
            defaultPrompt: defaultPrompt,
            modelIdentity: sam3Provider.modelIdentity,
            inputMaxSide: inputMaxSide,
        )
        self.sam3Configuration = configuration

        let repository = SubjectMaskRepository(
            configuration: configuration,
            stores: stores,
        )
        self.subjectMaskRepository = repository

        let segmentation = SegmentationService(
            provider: sam3Provider,
            stores: stores,
            maxSide: inputMaxSide,
        )
        self.sam3Segmentation = segmentation
        self.subjectMaskSelector = SubjectMaskSelector(
            repository: repository,
            segmentationService: segmentation,
        )

        self.activeSegmentationModelIdentity = nil
        self.capabilitySnapshot = RawCullAICapabilities(
            segmentationModels: [
                .sam3: .checking(expectedLocations: sam3CandidateURLs)
            ],
            clipModels: [
                .dataComp: .checking(expectedLocations: clipDataCompCandidateURLs),
                .openAI: .checking(expectedLocations: clipOpenAICandidateURLs)
            ],
            semanticSearchByCLIPModel: [
                .dataComp: .checking(expectedLocations: clipDataCompCandidateURLs),
                .openAI: .checking(expectedLocations: clipOpenAICandidateURLs)
            ],
            visionFeaturePrint: .available(location: nil),
            subjectMaskStorage: diskStoreResult.capability,
            inProcessMaskGeneration: .checking(
                expectedLocations: defaultSegmentationCandidateURLs,
            ),
        )
    }

    func capabilities() -> RawCullAICapabilities {
        capabilitySnapshot
    }

    func bindDeepAIReviewFeature(_ feature: DeepAIReviewFeature) {
        if let deepAIReviewFeature {
            assert(deepAIReviewFeature === feature)
            return
        }
        deepAIReviewFeature = feature
        activateSelectedSegmentationProvider(
            availability: capabilitySnapshot.inProcessMaskGeneration,
        )
    }

    func setSelectedSegmentationModel(_ model: RawCullSegmentationModel) {
        guard selectedSegmentationModel != model else { return }
        selectedSegmentationModel = model
        let status = capabilitySnapshot.segmentationModelStatus(for: model)
        capabilitySnapshot = RawCullAICapabilities(
            segmentationModels: capabilitySnapshot.segmentationModels,
            clipModels: capabilitySnapshot.clipModels,
            semanticSearchByCLIPModel: capabilitySnapshot.semanticSearchByCLIPModel,
            visionFeaturePrint: capabilitySnapshot.visionFeaturePrint,
            subjectMaskStorage: capabilitySnapshot.subjectMaskStorage,
            inProcessMaskGeneration: status,
        )
        activateSelectedSegmentationProvider(availability: status)
    }

    /// The single activation path for a complete installed-model snapshot.
    ///
    /// CLIP and SAM 3 invalidate their resource caches. Qwen validates or clears
    /// its inference runtime and returns the status that Settings should publish.
    func applyManagedModelLocations(
        _ locations: [RawCullAIModelDownloadID: URL],
    ) async -> QwenModelStatus {
        objectSegmentation = nil
        await sam3ModelResourceManager.setManagedCandidateURL(
            RawCullAIModelInclusion.includeSAM3 ? locations[.sam3] : nil,
        )
        await clipDataCompModelResourceManager.setManagedCandidateURL(
            locations[.clipDataComp],
        )
        await clipOpenAIModelResourceManager.setManagedCandidateURL(
            locations[.clipOpenAI],
        )
        guard let qwenURL = locations[.qwen3VL2B] else {
            await qwenInference.clear()
            return .notConfigured
        }
        return await qwenInference.validate(url: qwenURL.standardizedFileURL)
    }

    /// Semantic search exists only when the validated CLIP provider exposes
    /// PhotoAIKit's text-embedding and image/text comparison contracts.
    func semanticSearchService(
        clipModel: RawCullCLIPModel,
    ) -> (any RawCullSemanticSearchServicing)? {
        guard let provider = clipSimilarityProviders[clipModel] else { return nil }
        return RawCullCLIPSemanticSearchService(backend: provider)
    }

    /// Select the strongest requested similarity service whose validated model
    /// resources are currently available. Vision remains the safe runtime
    /// service until CLIP validation and provider construction both succeed.
    func similarityService(
        prefersCLIP: Bool,
        clipModel: RawCullCLIPModel,
    ) -> any RawCullSimilarityServicing {
        guard prefersCLIP else {
            Logger.process.debugMessageOnly(
                "RawCullAIModelRuntime: Vision similarity selected because CLIP is disabled",
            )
            return visionSimilarityService
        }
        guard let provider = clipSimilarityProviders[clipModel] else {
            let expectedLocation = clipSimilarityModelLocations[clipModel]?.path
                ?? paths.clipModelDirectory(for: clipModel).path
            Logger.process.warning(
                """
                RawCullAIModelRuntime: Vision similarity selected because no validated \
                \(clipModel.displayName, privacy: .public) CLIP provider is available; \
                expected/resolved model location=\(expectedLocation, privacy: .public)
                """,
            )
            return visionSimilarityService
        }
        guard let modelLocation = clipSimilarityModelLocations[clipModel] else {
            Logger.process.warning(
                """
                RawCullAIModelRuntime: Vision similarity selected because the validated \
                \(clipModel.displayName, privacy: .public) CLIP provider has no resolved \
                model location
                """,
            )
            return visionSimilarityService
        }
        let location = modelLocation.path
        Logger.process.info(
            """
            RawCullAIModelRuntime: \(clipModel.displayName, privacy: .public) CLIP \
            similarity selected; model=\(location, privacy: .public); \
            fingerprint=\(provider.backendDescriptor.modelFingerprint, privacy: .public)
            """,
        )
        let replacementProviderFactory: @Sendable () throws -> any ImageSimilarityArtifactProviding = {
            try CoreAICLIPProvider(modelBundleURL: modelLocation)
        }
        return RawCullCLIPSimilarityService(
            backend: provider,
            replacementProviderFactory: replacementProviderFactory,
        )
    }

    /// Refresh model resources outside the main actor and reuse validated
    /// providers while their candidate bundle metadata remains unchanged.
    @discardableResult
    func refreshCapabilities() async throws -> RawCullAICapabilities {
        async let sam3Load = sam3ModelResourceManager.load()
        async let clipDataCompLoad = clipDataCompModelResourceManager.load()
        async let clipOpenAILoad = clipOpenAIModelResourceManager.load()
        let (sam3, clipDataComp, clipOpenAI) = try await (
            sam3Load,
            clipDataCompLoad,
            clipOpenAILoad,
        )
        try Task.checkCancellation()

        segmentationProviders = [:]
        segmentationProviders[.sam3] = sam3.provider
        if let provider = sam3.provider {
            var objectStores: [any ObjectMaskStoring] = [objectMaskMemoryStore]
            if let objectMaskDiskStore {
                objectStores.append(objectMaskDiskStore)
            }
            objectSegmentation = try ObjectSegmentationService(
                provider: provider,
                stores: objectStores,
                maxSide: inputMaxSide,
                maximumInstanceCount: 8,
            )
        } else {
            objectSegmentation = nil
        }
        clipSimilarityProviders = [
            .dataComp: clipDataComp.provider,
            .openAI: clipOpenAI.provider
        ].compactMapValues(\.self)
        clipSimilarityModelLocations = [
            .dataComp: clipDataComp.capability.resource?.bundleURL,
            .openAI: clipOpenAI.capability.resource?.bundleURL
        ].compactMapValues(\.self)

        let sam3Status = Self.capabilityStatus(
            sam3.capability,
            providerInitializationFailure: sam3.providerInitializationFailure,
        )
        let clipDataCompStatus = Self.capabilityStatus(
            clipDataComp.capability,
            providerInitializationFailure: clipDataComp.providerInitializationFailure,
        )
        let clipOpenAIStatus = Self.capabilityStatus(
            clipOpenAI.capability,
            providerInitializationFailure: clipOpenAI.providerInitializationFailure,
        )
        let segmentationStatuses: [
            RawCullSegmentationModel: RawCullAICapabilityStatus
        ] = [
            .sam3: sam3Status
        ]
        let selectedSegmentationStatus = segmentationStatuses[
            selectedSegmentationModel,
        ] ?? .unavailable(
            reason: "The selected segmentation model was not configured.",
        )
        let capabilities = RawCullAICapabilities(
            segmentationModels: segmentationStatuses,
            clipModels: [
                .dataComp: clipDataCompStatus,
                .openAI: clipOpenAIStatus
            ],
            semanticSearchByCLIPModel: [
                .dataComp: Self.semanticSearchCapabilityStatus(
                    clipStatus: clipDataCompStatus,
                    provider: clipDataComp.provider,
                ),
                .openAI: Self.semanticSearchCapabilityStatus(
                    clipStatus: clipOpenAIStatus,
                    provider: clipOpenAI.provider,
                )
            ],
            visionFeaturePrint: .available(location: nil),
            subjectMaskStorage: subjectMaskStorageCapability,
            inProcessMaskGeneration: selectedSegmentationStatus,
        )
        capabilitySnapshot = capabilities
        activateSelectedSegmentationProvider(
            availability: capabilities.inProcessMaskGeneration,
        )
        return capabilities
    }

    private static func makeSubjectMaskDiskStore(
        at directory: URL,
    ) -> (store: SubjectMaskDiskStore?, capability: RawCullAICapabilityStatus) {
        do {
            return try (
                SubjectMaskDiskStore(cacheDirectory: directory),
                .available(location: directory),
            )
        } catch {
            return (
                nil,
                .invalid(location: directory, reason: String(describing: error)),
            )
        }
    }

    private static func capabilityStatus(
        _ status: ModelCapabilityStatus,
        providerInitializationFailure: String?,
    ) -> RawCullAICapabilityStatus {
        switch status {
        case let .available(resource):
            if let providerInitializationFailure {
                return .invalid(
                    location: resource.bundleURL,
                    reason: providerInitializationFailure,
                )
            }
            return .available(location: resource.bundleURL)

        case let .missing(candidates):
            return .missing(expectedLocations: candidates)

        case let .invalid(url, reason):
            return .invalid(location: url, reason: reason)
        }
    }

    private static func semanticSearchCapabilityStatus(
        clipStatus: RawCullAICapabilityStatus,
        provider: CoreAICLIPProvider?,
    ) -> RawCullSemanticSearchCapabilityStatus {
        if let provider {
            let location: URL? = if case let .available(resolvedLocation) = clipStatus {
                resolvedLocation
            } else {
                nil
            }
            return .ready(
                location: location,
                backend: provider.backendDescriptor,
            )
        }

        return switch clipStatus {
        case let .checking(expectedLocations):
            .checking(expectedLocations: expectedLocations)

        case let .missing(expectedLocations):
            .unavailable(
                reason: "Semantic search requires a valid CLIP model.",
                expectedLocations: expectedLocations,
            )

        case let .invalid(location, reason):
            .failed(location: location, reason: reason)

        case let .unavailable(reason):
            .unavailable(reason: reason, expectedLocations: [])

        case let .available(location):
            .failed(
                location: location,
                reason: "The validated CLIP resource did not create a text-capable provider.",
            )
        }
    }

    private func activateSelectedSegmentationProvider(
        availability: RawCullAICapabilityStatus,
    ) {
        let provider = segmentationProviders[selectedSegmentationModel]
        if let provider {
            installSegmentationProviderIfNeeded(provider)
        } else {
            installUnavailableSegmentationProviderIfNeeded()
        }
        deepAIReviewFeature?.install(
            service: provider.map { _ in
                RawCullDeepAIReviewPipeline(
                    selector: subjectMaskSelector,
                    maximumPixelSize: min(
                        inputMaxSide,
                        SharpnessScoringSizeOption.maximumPixelSize,
                    ),
                )
            },
            maskLoader: provider.flatMap { _ in
                subjectMaskDiskStore.map {
                    DeepAIReviewDiskMaskLoader(
                        repository: subjectMaskRepository,
                        diskStore: $0,
                    )
                }
            },
            availability: availability,
        )
    }

    private func installSegmentationProviderIfNeeded(_ provider: any SubjectSegmenting) {
        guard activeSegmentationModelIdentity != provider.modelIdentity else { return }
        activeSegmentationModelIdentity = provider.modelIdentity
        installSegmentationProvider(provider)
    }

    private func installUnavailableSegmentationProviderIfNeeded() {
        guard activeSegmentationModelIdentity != nil else { return }
        activeSegmentationModelIdentity = nil
        installSegmentationProvider(UnavailableSegmentationProvider())
    }

    private func installSegmentationProvider(_ provider: any SubjectSegmenting) {
        let configuration = SubjectMaskRepositoryConfiguration(
            defaultPrompt: defaultPrompt,
            modelIdentity: provider.modelIdentity,
            inputMaxSide: inputMaxSide,
        )
        let repository = SubjectMaskRepository(
            configuration: configuration,
            stores: subjectMaskStores,
        )
        sam3Configuration = configuration
        subjectMaskRepository = repository
        sam3Segmentation = SegmentationService(
            provider: provider,
            stores: subjectMaskStores,
            maxSide: inputMaxSide,
        )
        subjectMaskSelector = SubjectMaskSelector(
            repository: repository,
            segmentationService: sam3Segmentation,
        )
    }
}

private struct UnavailableSegmentationProvider: SubjectSegmenting {
    let modelIdentity = ModelIdentity(
        family: "sam3",
        name: "unavailable",
        assetName: "",
        cacheIdentifier: "coreai-sam3-local",
    )

    func segment(_: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        throw SubjectSegmentationError.providerFailure(
            "The selected segmentation model resources are not installed.",
        )
    }
}

/// Presentation-only access to masks persisted by Deep Review.
///
/// This deliberately bypasses the repository's memory-first lookup so the
/// preview verifies and displays the artifact written to the disk cache.
nonisolated struct DeepAIReviewDiskMaskLoader: DeepAIReviewMaskLoading, Sendable {
    let repository: SubjectMaskRepository
    let diskStore: SubjectMaskDiskStore

    func mask(
        for source: AIImageSource,
        prompt: SubjectSegmentationPrompt,
    ) async -> CGImage? {
        let key = await repository.storageKey(for: source, prompt: prompt)
        return await diskStore.load(for: key)?.mask
    }
}
