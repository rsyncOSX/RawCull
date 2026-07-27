import Foundation

/// Settings-facing state for AI integration readiness.
///
/// This model is the narrow boundary consumed by SwiftUI. It intentionally does
/// not expose PhotoAIKit providers, repositories, or the composition root.
@Observable @MainActor
final class RawCullAISettingsModel {
    static let useCLIPPreferenceKey = "RawCullAI.useCLIPForSimilarity"

    private(set) var capabilities: RawCullAICapabilities
    private(set) var savedBurstEvidence: RawCullSavedBurstEvidence?
    private(set) var savedBurstScanFailure: String?
    private(set) var isScanningSavedBurstData = false
    private(set) var isDeletingSavedBurstData = false

    var useCLIPForSimilarity: Bool {
        get { prefersCLIPForSimilarity }
        set { setUseCLIPForSimilarity(newValue) }
    }

    private var prefersCLIPForSimilarity: Bool
    @ObservationIgnored private let integration: RawCullAIIntegration
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private let similarityServiceDidChange: @MainActor (
        any RawCullSimilarityServicing
    ) -> Void
    @ObservationIgnored private let semanticSearchCapabilityDidChange: @MainActor (
        RawCullSemanticSearchCapabilityStatus,
        (any RawCullSemanticSearchServicing)?
    ) -> Void
    @ObservationIgnored private let evidenceScan: @Sendable () async throws
        -> RawCullSavedBurstEvidenceScanResult
    @ObservationIgnored private var refreshGeneration = 0

    init(
        integration: RawCullAIIntegration,
        evidenceScanner: RawCullSavedBurstEvidenceScanner? = nil,
        evidenceScan: (@Sendable () async throws -> RawCullSavedBurstEvidenceScanResult)? = nil,
        userDefaults: UserDefaults = .standard,
        similarityServiceDidChange: @escaping @MainActor (
            any RawCullSimilarityServicing
        ) -> Void = { _ in },
        semanticSearchCapabilityDidChange: @escaping @MainActor (
            RawCullSemanticSearchCapabilityStatus,
            (any RawCullSemanticSearchServicing)?
        ) -> Void = { _, _ in },
    ) {
        self.integration = integration
        self.userDefaults = userDefaults
        self.similarityServiceDidChange = similarityServiceDidChange
        self.semanticSearchCapabilityDidChange = semanticSearchCapabilityDidChange
        self.prefersCLIPForSimilarity = userDefaults.object(
            forKey: Self.useCLIPPreferenceKey,
        ) == nil ? true : userDefaults.bool(forKey: Self.useCLIPPreferenceKey)
        let scanner = evidenceScanner ?? RawCullSavedBurstEvidenceScanner(
            cacheDirectory: integration.paths.burstAnalysisDirectory,
        )
        self.evidenceScan = evidenceScan ?? {
            try await scanner.scan()
        }
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
            async let refreshedCapabilities = integration.refreshCapabilities()
            async let savedEvidence = evidenceScan()
            let (capabilities, result) = try await (
                refreshedCapabilities,
                savedEvidence,
            )
            try Task.checkCancellation()
            guard refreshGeneration == generation else { return }

            self.capabilities = capabilities
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

    func setUseCLIPForSimilarity(_ enabled: Bool) {
        guard prefersCLIPForSimilarity != enabled else { return }
        prefersCLIPForSimilarity = enabled
        userDefaults.set(enabled, forKey: Self.useCLIPPreferenceKey)
        applySimilarityPreference()
    }

    /// Intentionally empty until a safe saved-data deletion workflow exists.
    /// Existing RawCull burst analysis data must not be deleted by a placeholder.
    func deleteSavedBurstData() async {}

    private func applySimilarityPreference() {
        similarityServiceDidChange(
            integration.similarityService(prefersCLIP: prefersCLIPForSimilarity),
        )
        semanticSearchCapabilityDidChange(
            capabilities.semanticSearch,
            integration.semanticSearchService(),
        )
    }
}
