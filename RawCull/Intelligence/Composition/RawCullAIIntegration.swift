import CoreAICLIPBackend
import CoreAIEfficientSAMBackend
import CoreAISAM3Backend
import Foundation
import OSLog
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
import VisionFeaturePrintBackend

/// RawCull's single composition root for reusable AI services.
///
/// Feature models will receive narrow services from this root as each phase is
/// implemented. Views and `RawCullViewModel` do not traverse the composition root.
@MainActor
final class RawCullAIIntegration {
    let paths: RawCullAIPaths
    let sam3ModelResourceManager: RawCullAIModelResourceManager<CoreAISAM3Provider>
    let efficientSAMModelResourceManager:
        RawCullAIModelResourceManager<CoreAIEfficientSAMProvider>
    let clipDataCompModelResourceManager:
        RawCullAIModelResourceManager<CoreAICLIPProvider>
    let clipOpenAIModelResourceManager:
        RawCullAIModelResourceManager<CoreAICLIPProvider>

    let visionSimilarityProvider: VisionFeaturePrintBackend
    let visionSimilarityService: any RawCullSimilarityServicing
    private(set) var clipSimilarityProviders: [
        RawCullCLIPModel: CoreAICLIPProvider
    ]
    private(set) var clipSimilarityModelLocations: [RawCullCLIPModel: URL]

    let subjectMaskMemoryStore: SubjectMaskMemoryStore
    let subjectMaskDiskStore: SubjectMaskDiskStore?
    private(set) var subjectMaskRepository: SubjectMaskRepository
    private(set) var sam3Configuration: SubjectMaskRepositoryConfiguration
    private(set) var sam3Segmentation: SegmentationService
    private(set) var subjectMaskSelector: SubjectMaskSelector
    let deepAIReviewFeature: DeepAIReviewFeature

    private let subjectMaskStorageCapability: RawCullAICapabilityStatus
    private let subjectMaskStores: [any SubjectMaskStoring]
    private let defaultPrompt: SubjectSegmentationPrompt
    private let inputMaxSide: Int
    private var selectedSegmentationModel: RawCullSegmentationModel = .defaultSelection
    private var segmentationProviders: [RawCullSegmentationModel: any SubjectSegmenting] = [:]
    private var activeSegmentationModelIdentity: ModelIdentity?
    private var capabilitySnapshot: RawCullAICapabilities

    init(
        paths: RawCullAIPaths = .live(),
        bundle: Bundle = .main,
        allowsBundledModelFallback: Bool? = nil,
        defaultPrompt: SubjectSegmentationPrompt = .subject,
        inputMaxSide: Int = 4320,
    ) {
        self.paths = paths
        let allowsBundledModelFallback = allowsBundledModelFallback
            ?? Self.defaultAllowsBundledModelFallback
        let sam3CandidateURLs = RawCullAIModelCandidates.urls(
            installedDirectory: paths.sam3ModelDirectory,
            resourceName: "SAM3",
            bundle: bundle,
            allowsBundledFallback: allowsBundledModelFallback,
        )
        let efficientSAMCandidateURLs = RawCullAIModelCandidates.urls(
            installedDirectory: paths.efficientSAMModelDirectory,
            resourceName: RawCullSegmentationModel.efficientSAM.resourceName,
            bundle: bundle,
            allowsBundledFallback: allowsBundledModelFallback,
        )
        let defaultSegmentationCandidateURLs = switch RawCullSegmentationModel.defaultSelection {
        case .sam3: sam3CandidateURLs
        case .efficientSAM: efficientSAMCandidateURLs
        }
        let clipDataCompCandidateURLs = RawCullAIModelCandidates.urls(
            installedDirectory: paths.clipDataCompModelDirectory,
            resourceName: RawCullCLIPModel.dataComp.resourceName,
            bundle: bundle,
            allowsBundledFallback: allowsBundledModelFallback,
        )
        let clipOpenAICandidateURLs = RawCullAIModelCandidates.urls(
            installedDirectory: paths.clipOpenAIModelDirectory,
            resourceName: RawCullCLIPModel.openAI.resourceName,
            bundle: bundle,
            allowsBundledFallback: allowsBundledModelFallback,
        )
        self.sam3ModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: sam3CandidateURLs,
            factory: CoreAISAM3Provider.factory,
        )
        self.efficientSAMModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: efficientSAMCandidateURLs,
            factory: CoreAIEfficientSAMProvider.factory,
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

        self.deepAIReviewFeature = DeepAIReviewFeature(
            availability: .checking(
                expectedLocations: defaultSegmentationCandidateURLs,
            ),
        )
        self.activeSegmentationModelIdentity = nil
        self.capabilitySnapshot = RawCullAICapabilities(
            segmentationModels: [
                .sam3: .checking(expectedLocations: sam3CandidateURLs),
                .efficientSAM: .checking(expectedLocations: efficientSAMCandidateURLs)
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

    func setManagedModelLocations(
        _ locations: [RawCullAIModelDownloadID: URL],
    ) async {
        await sam3ModelResourceManager.setManagedCandidateURL(
            locations[.sam3],
        )
        await efficientSAMModelResourceManager.setManagedCandidateURL(
            locations[.efficientSAM],
        )
        await clipDataCompModelResourceManager.setManagedCandidateURL(
            locations[.clipDataComp],
        )
        await clipOpenAIModelResourceManager.setManagedCandidateURL(
            locations[.clipOpenAI],
        )
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
                "RawCullAIIntegration: Vision similarity selected because CLIP is disabled",
            )
            return visionSimilarityService
        }
        guard let provider = clipSimilarityProviders[clipModel] else {
            let expectedLocation = clipSimilarityModelLocations[clipModel]?.path
                ?? paths.clipModelDirectory(for: clipModel).path
            Logger.process.warning(
                """
                RawCullAIIntegration: Vision similarity selected because no validated \
                \(clipModel.displayName, privacy: .public) CLIP provider is available; \
                expected/resolved model location=\(expectedLocation, privacy: .public)
                """,
            )
            return visionSimilarityService
        }
        guard let modelLocation = clipSimilarityModelLocations[clipModel] else {
            Logger.process.warning(
                """
                RawCullAIIntegration: Vision similarity selected because the validated \
                \(clipModel.displayName, privacy: .public) CLIP provider has no resolved \
                model location
                """,
            )
            return visionSimilarityService
        }
        let location = modelLocation.path
        Logger.process.info(
            """
            RawCullAIIntegration: \(clipModel.displayName, privacy: .public) CLIP \
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
        async let efficientSAMLoad = efficientSAMModelResourceManager.load()
        async let clipDataCompLoad = clipDataCompModelResourceManager.load()
        async let clipOpenAILoad = clipOpenAIModelResourceManager.load()
        let (sam3, efficientSAM, clipDataComp, clipOpenAI) = try await (
            sam3Load,
            efficientSAMLoad,
            clipDataCompLoad,
            clipOpenAILoad,
        )
        try Task.checkCancellation()

        segmentationProviders = [:]
        segmentationProviders[.sam3] = sam3.provider
        segmentationProviders[.efficientSAM] = efficientSAM.provider
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
        let efficientSAMStatus = Self.capabilityStatus(
            efficientSAM.capability,
            providerInitializationFailure: efficientSAM.providerInitializationFailure,
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
            .sam3: sam3Status,
            .efficientSAM: efficientSAMStatus
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

    private static var defaultAllowsBundledModelFallback: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
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
        deepAIReviewFeature.install(
            service: provider.map { _ in
                RawCullDeepAIReviewPipeline(
                    selector: subjectMaskSelector,
                    maximumPixelSize: min(
                        inputMaxSide,
                        SharpnessScoringSizeOption.maximumPixelSize,
                    ),
                )
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
