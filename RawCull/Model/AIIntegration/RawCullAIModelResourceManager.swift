import Foundation
import PhotoAIContracts

/// Host-owned model location policy paired with a PhotoAIKit provider factory.
/// PhotoAIKit validates resources; RawCull decides where those resources live.
nonisolated struct RawCullAIModelResourceManager<Provider: Sendable>: Sendable {
    let candidateURLs: [URL]
    let factory: ModelProviderFactory<Provider>

    init(
        candidateURLs: [URL],
        factory: ModelProviderFactory<Provider>,
    ) {
        self.candidateURLs = candidateURLs
        self.factory = factory
    }

    func capability() -> ModelCapabilityStatus {
        factory.capability(in: candidateURLs)
    }

    func installedResource() -> ModelResource? {
        capability().resource
    }

    func makeProvider() throws -> Provider {
        try factory.makeFirstAvailable(in: candidateURLs)
    }
}

nonisolated enum RawCullAIModelCandidates {
    static func urls(
        installedDirectory: URL,
        resourceName: String,
        bundle: Bundle,
        allowsBundledFallback: Bool,
    ) -> [URL] {
        var candidates = [installedDirectory]
        guard allowsBundledFallback else { return candidates }

        let bundledCandidates = [
            bundle.url(forResource: resourceName, withExtension: nil, subdirectory: "Models"),
            bundle.url(forResource: resourceName, withExtension: nil, subdirectory: "Resources/Models"),
            bundle.url(forResource: resourceName, withExtension: nil),
            bundle.resourceURL?
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(resourceName, isDirectory: true),
            bundle.resourceURL?.appendingPathComponent(resourceName, isDirectory: true),
        ].compactMap(\.self)

        for candidate in bundledCandidates where !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        return candidates
    }
}
