import CoreAICLIPBackend
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
    let clipModelResourceManager: RawCullAIModelResourceManager<CoreAICLIPProvider>

    let visionSimilarityProvider: VisionFeaturePrintBackend
    let visionSimilarityService: any RawCullSimilarityServicing
    private(set) var clipSimilarityProvider: CoreAICLIPProvider?
    private(set) var clipSimilarityModelLocation: URL?

    let subjectMaskMemoryStore: SubjectMaskMemoryStore
    let subjectMaskDiskStore: SubjectMaskDiskStore?
    private(set) var subjectMaskRepository: SubjectMaskRepository
    private(set) var sam3Configuration: SubjectMaskRepositoryConfiguration
    private(set) var sam3Segmentation: SegmentationService
    private(set) var subjectMaskSelector: SubjectMaskSelector

    private let subjectMaskStorageCapability: RawCullAICapabilityStatus
    private let maskWorkerCapability: RawCullAICapabilityStatus
    private let subjectMaskStores: [any SubjectMaskStoring]
    private let defaultPrompt: SubjectSegmentationPrompt
    private let inputMaxSide: Int
    private var activeSAM3ModelIdentity: ModelIdentity?
    private var capabilitySnapshot: RawCullAICapabilities

    init(
        paths: RawCullAIPaths = .live(),
        bundle: Bundle = .main,
        allowsBundledModelFallback: Bool? = nil,
        maskWorkerExecutableNames: [String] = ["RawCullAIMaskWorker"],
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
        let clipCandidateURLs = RawCullAIModelCandidates.urls(
            installedDirectory: paths.clipModelDirectory,
            resourceName: "CLIP",
            bundle: bundle,
            allowsBundledFallback: allowsBundledModelFallback,
        )
        self.sam3ModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: sam3CandidateURLs,
            factory: CoreAISAM3Provider.factory,
        )
        self.clipModelResourceManager = RawCullAIModelResourceManager(
            candidateURLs: clipCandidateURLs,
            factory: CoreAICLIPProvider.factory,
        )
        self.clipSimilarityProvider = nil
        self.clipSimilarityModelLocation = nil

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

        let sam3Provider = UnavailableSAM3Provider()
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

        let maskWorkerCapability = Self.maskWorkerCapability(
            in: bundle,
            executableNames: maskWorkerExecutableNames,
        )
        self.maskWorkerCapability = maskWorkerCapability
        self.activeSAM3ModelIdentity = nil
        self.capabilitySnapshot = RawCullAICapabilities(
            sam3Model: .checking(expectedLocations: sam3CandidateURLs),
            clipModel: .checking(expectedLocations: clipCandidateURLs),
            visionFeaturePrint: .available(location: nil),
            subjectMaskStorage: diskStoreResult.capability,
            maskWorker: maskWorkerCapability,
        )
    }

    func capabilities() -> RawCullAICapabilities {
        capabilitySnapshot
    }

    /// Select the strongest requested similarity service whose validated model
    /// resources are currently available. Vision remains the safe runtime
    /// service until CLIP validation and provider construction both succeed.
    func similarityService(prefersCLIP: Bool) -> any RawCullSimilarityServicing {
        guard prefersCLIP else {
            Logger.process.debugMessageOnly(
                "RawCullAIIntegration: Vision similarity selected because CLIP is disabled",
            )
            return visionSimilarityService
        }
        guard let clipSimilarityProvider else {
            let expectedLocation = clipSimilarityModelLocation?.path
                ?? paths.clipModelDirectory.path
            Logger.process.warning(
                "RawCullAIIntegration: Vision similarity selected because no validated CLIP provider is available; expected/resolved model location=\(expectedLocation, privacy: .public)",
            )
            return visionSimilarityService
        }
        let location = clipSimilarityModelLocation?.path ?? "<unknown>"
        Logger.process.info(
            "RawCullAIIntegration: CLIP similarity selected; model=\(location, privacy: .public); fingerprint=\(clipSimilarityProvider.backendDescriptor.modelFingerprint, privacy: .public)",
        )
        return RawCullCLIPSimilarityService(
            backend: clipSimilarityProvider,
            visionBackend: visionSimilarityProvider,
        )
    }

    /// Refresh model resources outside the main actor and reuse validated
    /// providers while their candidate bundle metadata remains unchanged.
    @discardableResult
    func refreshCapabilities() async throws -> RawCullAICapabilities {
        async let sam3Load = sam3ModelResourceManager.load()
        async let clipLoad = clipModelResourceManager.load()
        let (sam3, clip) = try await (sam3Load, clipLoad)
        try Task.checkCancellation()

        if let provider = sam3.provider {
            installSAM3ProviderIfNeeded(provider)
        } else {
            installUnavailableSAM3ProviderIfNeeded()
        }
        clipSimilarityProvider = clip.provider
        clipSimilarityModelLocation = clip.capability.resource?.bundleURL

        let capabilities = RawCullAICapabilities(
            sam3Model: Self.capabilityStatus(
                sam3.capability,
                providerInitializationFailure: sam3.providerInitializationFailure,
            ),
            clipModel: Self.capabilityStatus(
                clip.capability,
                providerInitializationFailure: clip.providerInitializationFailure,
            ),
            visionFeaturePrint: .available(location: nil),
            subjectMaskStorage: subjectMaskStorageCapability,
            maskWorker: maskWorkerCapability,
        )
        capabilitySnapshot = capabilities
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

    private static func maskWorkerCapability(
        in bundle: Bundle,
        executableNames: [String],
    ) -> RawCullAICapabilityStatus {
        for executableName in executableNames {
            if let url = bundle.url(forAuxiliaryExecutable: executableName) {
                return .available(location: url)
            }
        }
        return .unavailable(
            reason: "The source-controlled SAM 3 mask worker has not been added yet.",
        )
    }

    private func installSAM3ProviderIfNeeded(_ provider: any SubjectSegmenting) {
        guard activeSAM3ModelIdentity != provider.modelIdentity else { return }
        activeSAM3ModelIdentity = provider.modelIdentity
        installSAM3Provider(provider)
    }

    private func installUnavailableSAM3ProviderIfNeeded() {
        guard activeSAM3ModelIdentity != nil else { return }
        activeSAM3ModelIdentity = nil
        installSAM3Provider(UnavailableSAM3Provider())
    }

    private func installSAM3Provider(_ provider: any SubjectSegmenting) {
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

private struct UnavailableSAM3Provider: SubjectSegmenting {
    let modelIdentity = ModelIdentity(
        family: "sam3",
        name: "unavailable",
        assetName: "",
        cacheIdentifier: "coreai-sam3-local",
    )

    func segment(_: SubjectSegmentationRequest) async throws -> SubjectSegmentationResult {
        throw SubjectSegmentationError.providerFailure(
            "SAM 3 model resources are not installed.",
        )
    }
}
