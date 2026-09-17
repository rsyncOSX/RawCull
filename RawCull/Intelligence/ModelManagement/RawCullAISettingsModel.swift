import Foundation

nonisolated enum RawCullQwenModelSource: String, Codable, Sendable {
    case managed
    case custom
}

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
    static let qwenModelPathPreferenceKey = "RawCullAI.qwenModelPath"
    static let qwenModelBookmarkPreferenceKey = "RawCullAI.qwenModelBookmark"
    static let qwenModelSourcePreferenceKey = "RawCullAI.qwenModelSource"

    private(set) var capabilities: RawCullAICapabilities
    private(set) var savedBurstEvidence: RawCullSavedBurstEvidence?
    private(set) var savedBurstScanFailure: String?
    private(set) var isScanningSavedBurstData = false
    private(set) var qwenModelStatus: QwenModelStatus = .notConfigured
    private(set) var qwenModelSource: RawCullQwenModelSource
    private(set) var managedQwenModelURL: URL?
    let modelManagementModel: RawCullAIModelManagementModel

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
    @ObservationIgnored private var qwenValidationTask: Task<Void, Never>?
    @ObservationIgnored private var qwenValidationGeneration = 0
    @ObservationIgnored private var activeQwenModelURL: URL?
    @ObservationIgnored private var securityScopedQwenModelURL: URL?
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
        modelManagementModel: RawCullAIModelManagementModel? = nil,
        modelDownloadCatalog: RawCullAIModelDownloadCatalog = .production,
        modelDownloadCoordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
        qwenModelManager: any QwenModelManaging = QwenModelManager(),
        qwenAnalysisFeature: RawCullQwenAnalysisFeature? = nil,
    ) {
        self.integration = integration
        self.userDefaults = userDefaults
        self.qwenModelManager = qwenModelManager
        self.qwenAnalysisFeature = qwenAnalysisFeature
            ?? RawCullQwenAnalysisFeature(modelManager: qwenModelManager)
        self.qwenModelSource = userDefaults.string(
            forKey: Self.qwenModelSourcePreferenceKey,
        ).flatMap(RawCullQwenModelSource.init(rawValue:)) ?? .managed
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
        self.modelManagementModel = modelManagementModel
            ?? RawCullAIModelManagementModel(
                paths: integration.paths,
                catalog: modelDownloadCatalog,
                coordinator: modelDownloadCoordinator,
                rawCullVersion: rawCullVersion,
            )
        self.capabilities = integration.capabilities()
        self.modelManagementModel.bindLocationsConsumer(self)
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
            managedQwenModelURL = locations[.qwen3VL2B]
            await reconcileQwenModelSource()
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
        await modelManagementModel.refresh()
    }

    func setQwenModelURL(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        guard startQwenSecurityScopedAccess(for: standardizedURL) else {
            applyQwenStatus(.invalid(
                url: standardizedURL,
                reason: "RawCull could not access the selected Qwen model folder.",
            ))
            return
        }

        userDefaults.set(
            standardizedURL.path,
            forKey: Self.qwenModelPathPreferenceKey,
        )
        let bookmark = try? standardizedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        )
        userDefaults.set(bookmark, forKey: Self.qwenModelBookmarkPreferenceKey)
        setQwenModelSource(.custom)
        validateQwenModel(at: standardizedURL)
    }

    func useManagedQwenModel() {
        setQwenModelSource(.managed)
        startQwenReconciliation()
    }

    func validateQwenModelAgain() {
        startQwenReconciliation()
    }

    func clearQwenModel() {
        qwenValidationTask?.cancel()
        qwenValidationTask = nil
        userDefaults.removeObject(forKey: Self.qwenModelPathPreferenceKey)
        userDefaults.removeObject(forKey: Self.qwenModelBookmarkPreferenceKey)
        if qwenModelSource == .custom {
            setQwenModelSource(.managed)
        }
        startQwenReconciliation()
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

    private func validateQwenModel(at url: URL) {
        let standardizedURL = url.standardizedFileURL
        activeQwenModelURL = standardizedURL
        qwenValidationTask?.cancel()
        qwenValidationGeneration &+= 1
        let generation = qwenValidationGeneration
        applyQwenStatus(.checking(standardizedURL))
        qwenValidationTask = Task { [weak self] in
            guard let self else { return }
            let status = await qwenModelManager.validate(url: standardizedURL)
            guard !Task.isCancelled,
                  qwenValidationGeneration == generation,
                  activeQwenModelURL == standardizedURL
            else { return }
            applyQwenStatus(status)
            qwenValidationTask = nil
        }
    }

    private func startQwenReconciliation() {
        qwenValidationTask?.cancel()
        qwenValidationTask = Task { [weak self] in
            await self?.reconcileQwenModelSource(
                cancelPendingValidation: false,
            )
        }
    }

    private func reconcileQwenModelSource(
        cancelPendingValidation: Bool = true,
    ) async {
        if cancelPendingValidation {
            qwenValidationTask?.cancel()
            qwenValidationTask = nil
        }
        qwenValidationGeneration &+= 1
        let generation = qwenValidationGeneration
        defer {
            if qwenValidationGeneration == generation {
                qwenValidationTask = nil
            }
        }

        let url: URL
        switch qwenModelSource {
        case .managed:
            securityScopedQwenModelURL?.stopAccessingSecurityScopedResource()
            securityScopedQwenModelURL = nil
            guard let managedQwenModelURL else {
                activeQwenModelURL = nil
                await qwenModelManager.clear()
                guard qwenValidationGeneration == generation else { return }
                applyQwenStatus(.notConfigured)
                return
            }
            url = managedQwenModelURL.standardizedFileURL

        case .custom:
            guard let customURL = resolvedQwenModelURL() else {
                activeQwenModelURL = nil
                await qwenModelManager.clear()
                guard qwenValidationGeneration == generation else { return }
                applyQwenStatus(.notConfigured)
                return
            }
            guard startQwenSecurityScopedAccess(for: customURL) else {
                activeQwenModelURL = nil
                await qwenModelManager.clear()
                guard qwenValidationGeneration == generation else { return }
                applyQwenStatus(.invalid(
                    url: customURL,
                    reason: "RawCull could not access the saved Qwen model folder.",
                ))
                return
            }
            url = customURL.standardizedFileURL
        }

        activeQwenModelURL = url
        applyQwenStatus(.checking(url))
        let status = await qwenModelManager.validate(url: url)
        guard !Task.isCancelled,
              qwenValidationGeneration == generation,
              activeQwenModelURL == url
        else { return }
        applyQwenStatus(status)
    }

    private func setQwenModelSource(_ source: RawCullQwenModelSource) {
        qwenModelSource = source
        userDefaults.set(source.rawValue, forKey: Self.qwenModelSourcePreferenceKey)
    }

    private func applyQwenStatus(_ status: QwenModelStatus) {
        qwenModelStatus = status
        qwenAnalysisFeature.updateModelStatus(status)
    }

    private func resolvedQwenModelURL() -> URL? {
        if let bookmark = userDefaults.data(forKey: Self.qwenModelBookmarkPreferenceKey) {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            ) {
                return url.standardizedFileURL
            }
        }
        return userDefaults.string(forKey: Self.qwenModelPathPreferenceKey)
            .map { URL(filePath: $0).standardizedFileURL }
    }

    private func startQwenSecurityScopedAccess(for url: URL) -> Bool {
        let standardizedURL = url.standardizedFileURL
        if securityScopedQwenModelURL == standardizedURL {
            return true
        }
        guard standardizedURL.startAccessingSecurityScopedResource() else {
            return false
        }
        securityScopedQwenModelURL?.stopAccessingSecurityScopedResource()
        securityScopedQwenModelURL = standardizedURL
        return true
    }
}
