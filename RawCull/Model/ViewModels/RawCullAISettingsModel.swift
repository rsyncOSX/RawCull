import Foundation

/// Settings-facing state for AI integration readiness.
///
/// This model is the narrow boundary consumed by SwiftUI. It intentionally does
/// not expose PhotoAIKit providers, repositories, or the composition root.
@Observable @MainActor
final class RawCullAISettingsModel {
    private(set) var capabilities: RawCullAICapabilities
    private(set) var savedBurstEvidence: RawCullSavedBurstEvidence?
    private(set) var savedBurstScanFailure: String?
    private(set) var isScanningSavedBurstData = false
    private(set) var isDeletingSavedBurstData = false

    /// Phase 2 will add persisted state and connect this preference to a
    /// similarity feature model. The setter is intentionally a no-op for now.
    var useCLIPForSimilarity: Bool {
        get { false }
        set { setUseCLIPForSimilarity(newValue) }
    }

    @ObservationIgnored private let integration: RawCullAIIntegration
    @ObservationIgnored private let evidenceScanner: RawCullSavedBurstEvidenceScanner

    init(
        integration: RawCullAIIntegration,
        evidenceScanner: RawCullSavedBurstEvidenceScanner? = nil,
    ) {
        self.integration = integration
        self.evidenceScanner = evidenceScanner ?? RawCullSavedBurstEvidenceScanner(
            cacheDirectory: integration.paths.burstAnalysisDirectory,
        )
        self.capabilities = integration.capabilities()
    }

    func refresh() async {
        capabilities = integration.capabilities()
        isScanningSavedBurstData = true
        defer { isScanningSavedBurstData = false }

        let scanner = evidenceScanner
        let result = await Task { @concurrent in
            scanner.scan()
        }.value
        guard !Task.isCancelled else { return }
        switch result {
        case let .success(evidence):
            savedBurstEvidence = evidence
            savedBurstScanFailure = nil
        case let .failure(reason):
            savedBurstEvidence = nil
            savedBurstScanFailure = reason
        }
    }

    /// Intentionally empty until Phase 2 connects CLIP similarity and settings
    /// persistence. Keeping the action here prevents the view from reaching into
    /// the AI composition root later.
    func setUseCLIPForSimilarity(_: Bool) {}

    /// Intentionally empty until saved AI artifacts are introduced. Existing
    /// RawCull burst analysis data must not be deleted by this placeholder.
    func deleteSavedBurstData() async {}
}
