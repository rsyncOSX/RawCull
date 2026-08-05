import Foundation

nonisolated struct RawCullAIModelDownloadPresentation: Equatable, Identifiable, Sendable {
    let descriptor: RawCullAIModelDownloadDescriptor
    let state: RawCullAIModelDownloadState
    let licenceAccepted: Bool

    var id: RawCullAIModelDownloadID {
        descriptor.id
    }
}

/// Settings-facing state for AI integration readiness.
///
/// This model is the narrow boundary consumed by SwiftUI. It intentionally does
/// not expose PhotoAIKit providers, repositories, or the composition root.
@Observable @MainActor
final class RawCullAISettingsModel {
    static let useCLIPPreferenceKey = "RawCullAI.useCLIPForSimilarity"
    static let selectedCLIPModelPreferenceKey = "RawCullAI.selectedCLIPModel"
    static let selectedSegmentationModelPreferenceKey =
        "RawCullAI.selectedSegmentationModel"

    private(set) var capabilities: RawCullAICapabilities
    private(set) var savedBurstEvidence: RawCullSavedBurstEvidence?
    private(set) var savedBurstScanFailure: String?
    private(set) var isScanningSavedBurstData = false
    private(set) var isDeletingSavedBurstData = false
    private(set) var modelDownloadStates: [
        RawCullAIModelDownloadID: RawCullAIModelDownloadState
    ]
    private(set) var acceptedLicenceModelIDs:
        Set<RawCullAIModelDownloadID> = []

    var modelDownloadPresentations: [RawCullAIModelDownloadPresentation] {
        modelDownloadCatalog.models.map { descriptor in
            RawCullAIModelDownloadPresentation(
                descriptor: descriptor,
                state: modelDownloadStates[descriptor.id] ?? .checking,
                licenceAccepted: acceptedLicenceModelIDs.contains(descriptor.id),
            )
        }
    }

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
    @ObservationIgnored private let similarityServiceDidChange: @MainActor (
        any RawCullSimilarityServicing,
    ) -> Void
    @ObservationIgnored private let semanticSearchCapabilityDidChange: @MainActor (
        RawCullSemanticSearchCapabilityStatus,
        (any RawCullSemanticSearchServicing)?,
    ) -> Void
    @ObservationIgnored private let evidenceScan: @Sendable () async throws
        -> RawCullSavedBurstEvidenceScanResult
    @ObservationIgnored private let modelDownloadCatalog:
        RawCullAIModelDownloadCatalog
    @ObservationIgnored private let modelDownloadCoordinator:
        RawCullAIModelDownloadCoordinator
    @ObservationIgnored private let rawCullVersion: String
    @ObservationIgnored private var managedModelLocations:
        [RawCullAIModelDownloadID: URL] = [:]
    @ObservationIgnored private var modelDownloadTasks:
        [RawCullAIModelDownloadID: Task<Void, Never>] = [:]
    @ObservationIgnored private var refreshGeneration = 0

    init(
        integration: RawCullAIIntegration,
        evidenceScanner: RawCullSavedBurstEvidenceScanner? = nil,
        evidenceScan: (@Sendable () async throws -> RawCullSavedBurstEvidenceScanResult)? = nil,
        userDefaults: UserDefaults = .standard,
        similarityServiceDidChange: @escaping @MainActor (
            any RawCullSimilarityServicing,
        ) -> Void = { _ in },
        semanticSearchCapabilityDidChange: @escaping @MainActor (
            RawCullSemanticSearchCapabilityStatus,
            (any RawCullSemanticSearchServicing)?,
        ) -> Void = { _, _ in },
        modelDownloadCatalog: RawCullAIModelDownloadCatalog = .production,
        modelDownloadCoordinator: RawCullAIModelDownloadCoordinator? = nil,
        rawCullVersion: String? = nil,
    ) {
        self.integration = integration
        self.userDefaults = userDefaults
        self.similarityServiceDidChange = similarityServiceDidChange
        self.semanticSearchCapabilityDidChange = semanticSearchCapabilityDidChange
        self.prefersCLIPForSimilarity = userDefaults.object(
            forKey: Self.useCLIPPreferenceKey,
        ) == nil ? true : userDefaults.bool(forKey: Self.useCLIPPreferenceKey)
        self.selectedModel = userDefaults.string(
            forKey: Self.selectedCLIPModelPreferenceKey,
        )
        .flatMap(RawCullCLIPModel.init(rawValue:))
        ?? .defaultSelection
        self.selectedSegmenter = userDefaults.string(
            forKey: Self.selectedSegmentationModelPreferenceKey,
        )
        .flatMap(RawCullSegmentationModel.init(rawValue:))
        ?? .defaultSelection
        let scanner = evidenceScanner ?? RawCullSavedBurstEvidenceScanner(
            cacheDirectory: integration.paths.burstAnalysisDirectory,
        )
        self.evidenceScan = evidenceScan ?? {
            try await scanner.scan()
        }
        self.modelDownloadCatalog = modelDownloadCatalog
        self.modelDownloadCoordinator = modelDownloadCoordinator
            ?? .live(paths: integration.paths)
        self.rawCullVersion = rawCullVersion
            ?? Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString",
            ) as? String
            ?? "unknown"
        self.modelDownloadStates = Dictionary(
            uniqueKeysWithValues: modelDownloadCatalog.models.map {
                ($0.id, .checking)
            },
        )
        self.capabilities = integration.capabilities()
        integration.setSelectedSegmentationModel(selectedSegmenter)
        self.capabilities = integration.capabilities()
    }

    func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isScanningSavedBurstData = true
        defer {
            if refreshGeneration == generation {
                isScanningSavedBurstData = false
            }
        }

        do {
            let downloadSnapshot = await modelDownloadCoordinator.snapshot()
            try Task.checkCancellation()
            await integration.setManagedModelLocations(
                downloadSnapshot.managedModelLocations,
            )
            async let refreshedCapabilities = integration.refreshCapabilities()
            async let savedEvidence = evidenceScan()
            let (capabilities, result) = try await (
                refreshedCapabilities,
                savedEvidence,
            )
            try Task.checkCancellation()
            guard refreshGeneration == generation else { return }

            self.capabilities = capabilities
            modelDownloadStates = downloadSnapshot.states
            managedModelLocations = downloadSnapshot.managedModelLocations
            acceptedLicenceModelIDs =
                downloadSnapshot.acceptedLicenceModelIDs
            applySimilarityPreference()
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

    func acceptModelLicence(
        for id: RawCullAIModelDownloadID,
    ) async {
        do {
            try await modelDownloadCoordinator.acceptLicence(
                for: id,
                rawCullVersion: rawCullVersion,
            )
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            modelDownloadStates[id] = .failed(
                message: String(describing: error),
            )
        }
    }

    func startModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) {
        guard modelDownloadTasks[id] == nil else { return }
        guard let state = modelDownloadStates[id] else { return }
        guard state.canStartDownload else { return }

        modelDownloadStates[id] = .downloading(progress: 0)
        modelDownloadTasks[id] = Task { [weak self] in
            guard let self else { return }
            await performModelDownload(id)
        }
    }

    func cancelModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) {
        modelDownloadTasks[id]?.cancel()
    }

    func removeManagedModel(
        _ id: RawCullAIModelDownloadID,
    ) async {
        guard modelDownloadTasks[id] == nil else { return }
        modelDownloadStates[id] = .removing
        do {
            try await modelDownloadCoordinator.remove(id)
            managedModelLocations[id] = nil
            await integration.setManagedModelLocations(managedModelLocations)
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            modelDownloadStates[id] = .failed(
                message: String(describing: error),
            )
        }
    }

    func setUseCLIPForSimilarity(_ enabled: Bool) {
        guard prefersCLIPForSimilarity != enabled else { return }
        prefersCLIPForSimilarity = enabled
        userDefaults.set(enabled, forKey: Self.useCLIPPreferenceKey)
        applySimilarityPreference()
    }

    func setSelectedCLIPModel(_ model: RawCullCLIPModel) {
        guard selectedModel != model else { return }
        selectedModel = model
        userDefaults.set(model.rawValue, forKey: Self.selectedCLIPModelPreferenceKey)
        applySimilarityPreference()
    }

    func setSelectedSegmentationModel(_ model: RawCullSegmentationModel) {
        guard selectedSegmenter != model else { return }
        selectedSegmenter = model
        userDefaults.set(
            model.rawValue,
            forKey: Self.selectedSegmentationModelPreferenceKey,
        )
        integration.setSelectedSegmentationModel(model)
        capabilities = integration.capabilities()
    }

    /// Intentionally empty until a safe saved-data deletion workflow exists.
    /// Existing RawCull burst analysis data must not be deleted by a placeholder.
    func deleteSavedBurstData() async {}

    private func performModelDownload(
        _ id: RawCullAIModelDownloadID,
    ) async {
        defer { modelDownloadTasks[id] = nil }

        do {
            let location = try await modelDownloadCoordinator.download(
                id,
                progress: { [weak self] progress in
                    guard let self, !Task.isCancelled else { return }
                    modelDownloadStates[id] = .downloading(
                        progress: min(max(progress, 0), 1),
                    )
                },
            )
            try Task.checkCancellation()
            modelDownloadStates[id] = .validating
            managedModelLocations[id] = location
            await integration.setManagedModelLocations(managedModelLocations)
            await refresh()
        } catch is CancellationError {
            let snapshot = await modelDownloadCoordinator.snapshot()
            modelDownloadStates[id] = snapshot.states[id] ?? .ready
        } catch {
            modelDownloadStates[id] = .failed(
                message: String(describing: error),
            )
        }
    }

    private func applySimilarityPreference() {
        similarityServiceDidChange(
            integration.similarityService(
                prefersCLIP: prefersCLIPForSimilarity,
                clipModel: selectedModel,
            ),
        )
        semanticSearchCapabilityDidChange(
            selectedSemanticSearchStatus,
            integration.semanticSearchService(clipModel: selectedModel),
        )
    }
}

private nonisolated extension RawCullAIModelDownloadState {
    var canStartDownload: Bool {
        switch self {
        case .ready, .failed:
            true

        case .checking, .unavailable, .licenceRequired, .notConfigured,
             .downloading, .validating, .installed, .removing:
            false
        }
    }
}
