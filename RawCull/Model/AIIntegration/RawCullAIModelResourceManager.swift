import Foundation
import PhotoAIContracts

/// One validated model-resource result. Provider construction failures remain
/// separate from bundle capability so Settings can explain which stage failed.
nonisolated struct RawCullAIModelResourceLoad<Provider: Sendable>: Sendable {
    let capability: ModelCapabilityStatus
    let provider: Provider?
    let providerInitializationFailure: String?
}

/// Actor-owned model validation and provider construction.
///
/// The actor keeps hashing and provider setup off the main actor. A lightweight
/// file-metadata snapshot avoids repeating PhotoAIKit's full bundle validation
/// when none of the candidate bundle contents changed.
actor RawCullAIModelResourceManager<Provider: Sendable> {
    nonisolated let candidateURLs: [URL]
    nonisolated let factory: ModelProviderFactory<Provider>

    private var managedCandidateURL: URL?
    private var cachedSnapshot: RawCullAIModelResourceSnapshot?
    private var cachedLoad: RawCullAIModelResourceLoad<Provider>?

    init(
        candidateURLs: [URL],
        factory: ModelProviderFactory<Provider>,
    ) {
        self.candidateURLs = candidateURLs
        self.factory = factory
    }

    func setManagedCandidateURL(_ url: URL?) {
        guard managedCandidateURL != url else { return }
        managedCandidateURL = url
        cachedSnapshot = nil
        cachedLoad = nil
    }

    func load() throws -> RawCullAIModelResourceLoad<Provider> {
        try Task.checkCancellation()
        let resolvedCandidateURLs = (managedCandidateURL.map { [$0] } ?? [])
            + candidateURLs
        let snapshot = RawCullAIModelResourceSnapshot(
            candidateURLs: resolvedCandidateURLs,
        )
        try Task.checkCancellation()

        if snapshot == cachedSnapshot, let cachedLoad {
            return cachedLoad
        }

        let capability = factory.capability(in: resolvedCandidateURLs)
        try Task.checkCancellation()

        let provider: Provider?
        let providerInitializationFailure: String?
        if let resource = capability.resource {
            do {
                provider = try factory.makeProvider(from: resource)
                providerInitializationFailure = nil
            } catch {
                provider = nil
                providerInitializationFailure = String(describing: error)
            }
        } else {
            provider = nil
            providerInitializationFailure = nil
        }

        let load = RawCullAIModelResourceLoad(
            capability: capability,
            provider: provider,
            providerInitializationFailure: providerInitializationFailure,
        )
        cachedSnapshot = snapshot
        cachedLoad = load
        try Task.checkCancellation()
        return load
    }
}

/// A content-change key that reads file metadata rather than model bytes.
/// PhotoAIKit remains authoritative for cryptographic verification whenever the
/// snapshot changes; this key only determines whether that result can be reused.
private nonisolated struct RawCullAIModelResourceSnapshot: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        enum Kind: String, Sendable {
            case directory
            case file
            case missing
            case other
            case unreadable
        }

        let path: String
        let kind: Kind
        let byteCount: Int?
        let modificationDate: Date?
        let resolvedPath: String?

        init(url: URL) {
            path = url.path
            do {
                let values = try url.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ])
                if values.isDirectory == true {
                    kind = .directory
                } else if values.isRegularFile == true {
                    kind = .file
                } else {
                    kind = .other
                }
                byteCount = values.fileSize
                modificationDate = values.contentModificationDate
                resolvedPath = values.isSymbolicLink == true
                    ? url.resolvingSymlinksInPath().path
                    : nil
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                kind = .missing
                byteCount = nil
                modificationDate = nil
                resolvedPath = nil
            } catch {
                kind = .unreadable
                byteCount = nil
                modificationDate = nil
                resolvedPath = nil
            }
        }
    }

    private let entries: [Entry]

    init(candidateURLs: [URL]) {
        var entries: [Entry] = []
        for candidate in candidateURLs {
            let candidateEntry = Entry(url: candidate)
            entries.append(candidateEntry)
            guard candidateEntry.kind == .directory else { continue }

            guard let enumerator = FileManager.default.enumerator(
                at: candidate,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
            ) else {
                continue
            }
            while let url = enumerator.nextObject() as? URL {
                entries.append(Entry(url: url))
            }
        }
        self.entries = entries.sorted { $0.path < $1.path }
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
            bundle.resourceURL?.appendingPathComponent(resourceName, isDirectory: true)
        ].compactMap(\.self)

        for candidate in bundledCandidates where !candidates.contains(candidate) {
            candidates.append(candidate)
        }
        return candidates
    }
}
