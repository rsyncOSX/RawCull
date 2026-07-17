import CoreAICLIPBackend
import CoreAISAM3Backend
import Foundation
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
    let clipSimilarityProvider: CoreAICLIPProvider?

    let subjectMaskMemoryStore: SubjectMaskMemoryStore
    let subjectMaskDiskStore: SubjectMaskDiskStore?
    let subjectMaskRepository: SubjectMaskRepository
    let sam3Configuration: SubjectMaskRepositoryConfiguration
    let sam3Segmentation: SegmentationService
    let subjectMaskSelector: SubjectMaskSelector

    private let subjectMaskStorageCapability: RawCullAICapabilityStatus
    private let maskWorkerCapability: RawCullAICapabilityStatus
    private let sam3ProviderInitializationFailure: String?
    private let clipProviderInitializationFailure: String?

    init(
        paths: RawCullAIPaths = .live(),
        bundle: Bundle = .main,
        allowsBundledModelFallback: Bool? = nil,
        maskWorkerExecutableNames: [String] = ["RawCullAIMaskWorker"],
        defaultPrompt: SubjectSegmentationPrompt = .subject,
        inputMaxSide: Int = 4_320,
    ) {
        self.paths = paths
        let allowsBundledModelFallback = allowsBundledModelFallback
            ?? Self.defaultAllowsBundledModelFallback

        let sam3Manager = RawCullAIModelResourceManager(
            candidateURLs: RawCullAIModelCandidates.urls(
                installedDirectory: paths.sam3ModelDirectory,
                resourceName: "SAM3",
                bundle: bundle,
                allowsBundledFallback: allowsBundledModelFallback,
            ),
            factory: CoreAISAM3Provider.factory,
        )
        let clipManager = RawCullAIModelResourceManager(
            candidateURLs: RawCullAIModelCandidates.urls(
                installedDirectory: paths.clipModelDirectory,
                resourceName: "CLIP",
                bundle: bundle,
                allowsBundledFallback: allowsBundledModelFallback,
            ),
            factory: CoreAICLIPProvider.factory,
        )
        self.sam3ModelResourceManager = sam3Manager
        self.clipModelResourceManager = clipManager

        let sam3ProviderResult = Self.makeSAM3Provider(using: sam3Manager)
        let sam3Provider = sam3ProviderResult.provider
        self.sam3ProviderInitializationFailure = sam3ProviderResult.failure

        let clipProviderResult = Self.makeCLIPProvider(using: clipManager)
        self.clipSimilarityProvider = clipProviderResult.provider
        self.clipProviderInitializationFailure = clipProviderResult.failure
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
        self.maskWorkerCapability = Self.maskWorkerCapability(
            in: bundle,
            executableNames: maskWorkerExecutableNames,
        )
    }

    func capabilities() -> RawCullAICapabilities {
        RawCullAICapabilities(
            sam3Model: Self.capabilityStatus(
                sam3ModelResourceManager.capability(),
                providerInitializationFailure: sam3ProviderInitializationFailure,
            ),
            clipModel: Self.capabilityStatus(
                clipModelResourceManager.capability(),
                providerInitializationFailure: clipProviderInitializationFailure,
            ),
            visionFeaturePrint: .available(location: nil),
            subjectMaskStorage: subjectMaskStorageCapability,
            maskWorker: maskWorkerCapability,
        )
    }

    private static var defaultAllowsBundledModelFallback: Bool {
        #if DEBUG
            true
        #else
            false
        #endif
    }

    private static func makeSAM3Provider(
        using manager: RawCullAIModelResourceManager<CoreAISAM3Provider>,
    ) -> (provider: any SubjectSegmenting, failure: String?) {
        do {
            return (try manager.makeProvider(), nil)
        } catch {
            return (
                UnavailableSAM3Provider(),
                manager.installedResource() == nil ? nil : String(describing: error),
            )
        }
    }

    private static func makeCLIPProvider(
        using manager: RawCullAIModelResourceManager<CoreAICLIPProvider>,
    ) -> (provider: CoreAICLIPProvider?, failure: String?) {
        do {
            return (try manager.makeProvider(), nil)
        } catch {
            return (
                nil,
                manager.installedResource() == nil ? nil : String(describing: error),
            )
        }
    }

    private static func makeSubjectMaskDiskStore(
        at directory: URL,
    ) -> (store: SubjectMaskDiskStore?, capability: RawCullAICapabilityStatus) {
        do {
            return (
                try SubjectMaskDiskStore(cacheDirectory: directory),
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
