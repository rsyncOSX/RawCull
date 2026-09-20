import Foundation

/// Settings-facing state for AI integration readiness.
///
/// This model is the narrow boundary consumed by SwiftUI. It intentionally does
/// not expose PhotoAIKit providers, repositories, or the composition root.
@Observable @MainActor
final class RawCullAISettingsModel: RawCullAIManagedModelLocationsApplying {
    static let useCLIPPreferenceKey = "RawCullAI.useCLIPForSimilarity"
    static let selectedCLIPModelPreferenceKey = "RawCullAI.selectedCLIPModel"
    static let selectedSegmentationModelPreferenceKey =
        "RawCullAI.selectedSegmentationModel"

    private(set) var capabilities: RawCullAICapabilities
    private(set) var savedBurstEvidence: RawCullSavedBurstEvidence?
    private(set) var savedBurstScanFailure: String?
    private(set) var isScanningSavedBurstData = false
    private(set) var qwenModelStatus: RawCullAICapabilityStatus = .checking(
        expectedLocations: [],
    )
    let modelDownloadsModel: RawCullAIModelDownloadsModel

    var useCLIPForSimilarity: Bool {
        get { prefersCLIPForSimilarity }
        set { setUseCLIPForSimilarity(newValue) }
    }

    var selectedCLIPModel: RawCullCLIPModel {
        get { selectedModel }
        set { setSelectedCLIPModel(newValue) }
    }

    var selectedCLIPModelStatus: RawCullAICapabilityStatus {
        capabilities.clipModelStatus(for: selectedModel)
    }

    var selectedSemanticSearchStatus: RawCullSemanticSearchCapabilityStatus {
        capabilities.semanticSearchStatus(for: selectedModel)
    }

    var selectedSegmentationModel: RawCullSegmentationModel {
        get { selectedSegmenter }
        set { setSelectedSegmentationModel(newValue) }
    }

    var selectedSegmentationModelStatus: RawCullAICapabilityStatus {
        capabilities.segmentationModelStatus(for: selectedSegmenter)
    }

    private var prefersCLIPForSimilarity: Bool
    private var selectedModel: RawCullCLIPModel
    private var selectedSegmenter: RawCullSegmentationModel
    @ObservationIgnored private let integration: RawCullAIIntegration
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let qwenModelManager: any QwenModelManaging
    @ObservationIgnored private let qwenAnalysisFeature: RawCullQwenAnalysisFeature
    @ObservationIgnored private var qwenValidationGeneration = 0
    @ObservationIgnored private weak var configurationConsumer:
        (any RawCullIntelligenceConfigurationApplying)?
    @ObservationIgnored private var configurationRevision: UInt64 = 0
    @ObservationIgnored private let evidenceScan: @Sendable () async throws
        -> RawCullSavedBurstEvidenceScanResult
    @ObservationIgnored private var refreshGeneration = 0

    init(
        integration: RawCullAIIntegration,
        evidenceScanner: RawCullSavedBurstEvidenceScanner? = nil,
        evidenceScan: (@Sendable () async throws -> RawCullSavedBurstEvidenceScanResult)? = nil,
        userDefaults: UserDefaults = .standard,
        modelDownloadsModel: RawCullAIModelDownloadsModel? = nil,
        modelDownloadCatalog: RawCullAIModelDownloadCatalog = .production,
        modelDownloadCoordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
        qwenModelManager: any QwenModelManaging,
        qwenAnalysisFeature: RawCullQwenAnalysisFeature? = nil,
    ) {
        self.integration = integration
        self.userDefaults = userDefaults
        self.qwenModelManager = qwenModelManager
        self.qwenAnalysisFeature = qwenAnalysisFeature
            ?? RawCullQwenAnalysisFeature(modelManager: qwenModelManager)
        self.prefersCLIPForSimilarity = userDefaults.object(
            forKey: Self.useCLIPPreferenceKey,
        ) == nil ? true : userDefaults.bool(forKey: Self.useCLIPPreferenceKey)
        let savedCLIPModel = userDefaults.string(
            forKey: Self.selectedCLIPModelPreferenceKey,
        )
        .flatMap(RawCullCLIPModel.init(rawValue:))
        self.selectedModel = savedCLIPModel.flatMap { model in
            RawCullAIModelInclusion.clipModels.contains(model) ? model : nil
        }
            ?? RawCullAIModelInclusion.clipModels.first
            ?? .defaultSelection
        let savedSegmentationModel = userDefaults.string(
            forKey: Self.selectedSegmentationModelPreferenceKey,
        )
        .flatMap(RawCullSegmentationModel.init(rawValue:))
        self.selectedSegmenter = savedSegmentationModel.flatMap { model in
            RawCullAIModelInclusion.segmentationModels.contains(model) ? model : nil
        }
            ?? RawCullAIModelInclusion.segmentationModels.first
            ?? .defaultSelection
        let scanner = evidenceScanner ?? RawCullSavedBurstEvidenceScanner(
            cacheDirectory: integration.paths.burstAnalysisDirectory,
        )
        self.evidenceScan = evidenceScan ?? {
            try await scanner.scan()
        }
        self.modelDownloadsModel = modelDownloadsModel
            ?? RawCullAIModelDownloadsModel(
                paths: integration.paths,
                catalog: modelDownloadCatalog,
                coordinator: modelDownloadCoordinator,
                rawCullVersion: rawCullVersion,
            )
        self.capabilities = integration.capabilities()
        self.modelDownloadsModel.bindLocationsConsumer(self)
    }

    func sharesQwenRuntimeIdentity(
        modelManager: any QwenModelManaging,
        analysisFeature: RawCullQwenAnalysisFeature,
    ) -> Bool {
        qwenModelManager === modelManager && qwenAnalysisFeature === analysisFeature
    }

    func applyManagedModelLocations(
        _ locations: [RawCullAIModelDownloadID: URL],
    ) async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isScanningSavedBurstData = true
        defer {
            if refreshGeneration == generation {
                isScanningSavedBurstData = false
            }
        }

        do {
            await integration.setManagedModelLocations(locations)
            await applyManagedQwenModel(at: locations[.qwen3VL2B])
            async let refreshedCapabilities = integration.refreshCapabilities()
            async let savedEvidence = evidenceScan()
            let (capabilities, result) = try await (
                refreshedCapabilities,
                savedEvidence,
            )
            try Task.checkCancellation()
            guard refreshGeneration == generation else { return }

            self.capabilities = capabilities
            publishConfiguration()
            switch result {
            case let .success(evidence):
                savedBurstEvidence = evidence
                savedBurstScanFailure = nil

            case let .failure(reason):
                savedBurstEvidence = nil
                savedBurstScanFailure = reason
            }
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == generation else { return }
            savedBurstEvidence = nil
            savedBurstScanFailure = String(describing: error)
        }
    }

    func configurationSnapshot(
        revision: UInt64 = 0,
    ) -> RawCullIntelligenceConfiguration {
        RawCullIntelligenceConfiguration(
            revision: revision,
            similarity: RawCullSimilarityConfiguration(
                service: integration.similarityService(
                    prefersCLIP: prefersCLIPForSimilarity,
                    clipModel: selectedModel,
                ),
            ),
            semanticSearch: RawCullSemanticSearchConfiguration(
                capability: selectedSemanticSearchStatus,
                service: integration.semanticSearchService(clipModel: selectedModel),
            ),
            segmentationModel: selectedSegmenter,
        )
    }

    func bindConfigurationConsumer(
        _ consumer: any RawCullIntelligenceConfigurationApplying,
    ) {
        precondition(
            configurationConsumer == nil,
            "RawCullAISettingsModel configuration consumer may only be bound once.",
        )
        configurationConsumer = consumer
        publishConfiguration()
    }

    func refresh() async {
        await modelDownloadsModel.refresh()
    }

    func setUseCLIPForSimilarity(_ enabled: Bool) {
        guard prefersCLIPForSimilarity != enabled else { return }
        prefersCLIPForSimilarity = enabled
        userDefaults.set(enabled, forKey: Self.useCLIPPreferenceKey)
        publishConfiguration()
    }

    func setSelectedCLIPModel(_ model: RawCullCLIPModel) {
        guard RawCullAIModelInclusion.clipModels.contains(model) else { return }
        guard selectedModel != model else { return }
        selectedModel = model
        userDefaults.set(model.rawValue, forKey: Self.selectedCLIPModelPreferenceKey)
        publishConfiguration()
    }

    func setSelectedSegmentationModel(_ model: RawCullSegmentationModel) {
        guard RawCullAIModelInclusion.segmentationModels.contains(model) else {
            return
        }
        guard selectedSegmenter != model else { return }
        selectedSegmenter = model
        userDefaults.set(
            model.rawValue,
            forKey: Self.selectedSegmentationModelPreferenceKey,
        )
        publishConfiguration()
    }

    private func publishConfiguration() {
        guard let configurationConsumer else { return }
        configurationRevision &+= 1
        capabilities = configurationConsumer.apply(
            configuration: configurationSnapshot(
                revision: configurationRevision,
            ),
        )
    }

    private func applyManagedQwenModel(at url: URL?) async {
        qwenValidationGeneration &+= 1
        let generation = qwenValidationGeneration
        guard let url else {
            await qwenModelManager.clear()
            guard qwenValidationGeneration == generation else { return }
            applyQwenStatus(.notConfigured)
            return
        }

        let standardizedURL = url.standardizedFileURL
        applyQwenStatus(.checking(standardizedURL))
        let status = await qwenModelManager.validate(url: standardizedURL)
        guard !Task.isCancelled,
              qwenValidationGeneration == generation
        else { return }
        applyQwenStatus(status)
    }

    private func applyQwenStatus(_ status: QwenModelStatus) {
        qwenModelStatus = status.capabilityStatus
        qwenAnalysisFeature.updateModelStatus(status)
    }
}

private nonisolated extension QwenModelStatus {
    var capabilityStatus: RawCullAICapabilityStatus {
        switch self {
        case .notConfigured:
            .missing(expectedLocations: [])

        case let .checking(url):
            .checking(expectedLocations: [url])

        case let .available(url, _):
            .available(location: url)

        case let .missing(url):
            .missing(expectedLocations: [url])

        case let .invalid(url, reason):
            .invalid(location: url, reason: reason)
        }
    }
}
