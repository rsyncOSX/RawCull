import Foundation

nonisolated struct RawCullAIModelLicenceAcceptance: Codable, Equatable, Sendable {
    let modelID: RawCullAIModelDownloadID
    let modelVersion: String
    let licenceName: String
    let licenceVersion: String?
    let licenceTextSHA256: String
    let acceptedAt: Date
    let rawCullVersion: String

    func matches(
        descriptor: RawCullAIModelDownloadDescriptor,
    ) -> Bool {
        modelID == descriptor.id
            && modelVersion == descriptor.modelVersion
            && licenceName == descriptor.licence.name
            && licenceVersion == descriptor.licence.version
            && licenceTextSHA256 == descriptor.licence.textSHA256
    }
}

nonisolated protocol RawCullAIModelLicenceAcceptanceStoring: Sendable {
    func acceptance(
        for descriptor: RawCullAIModelDownloadDescriptor,
    ) async throws -> RawCullAIModelLicenceAcceptance?

    func recordAcceptance(
        for descriptor: RawCullAIModelDownloadDescriptor,
        rawCullVersion: String,
    ) async throws
}

actor RawCullAIModelLicenceAcceptanceFileStore:
    RawCullAIModelLicenceAcceptanceStoring
{
    private struct Store: Codable, Sendable {
        var acceptances: [RawCullAIModelLicenceAcceptance]
    }

    private let fileURL: URL
    private let licenceBundle: Bundle
    private var cachedStore: Store?

    init(
        fileURL: URL,
        licenceBundle: Bundle = .main,
    ) {
        self.fileURL = fileURL
        self.licenceBundle = licenceBundle
    }

    func acceptance(
        for descriptor: RawCullAIModelDownloadDescriptor,
    ) throws -> RawCullAIModelLicenceAcceptance? {
        let store = try load()
        return store.acceptances.first {
            $0.modelID == descriptor.id && $0.matches(descriptor: descriptor)
        }
    }

    func recordAcceptance(
        for descriptor: RawCullAIModelDownloadDescriptor,
        rawCullVersion: String,
    ) throws {
        guard descriptor.licence.requiresExplicitAcceptance else { return }
        guard descriptor.releaseReadiness.isReady else {
            throw RawCullAIModelDownloadError.releaseBlocked(descriptor.displayName)
        }
        guard let textSHA256 = descriptor.licence.textSHA256,
              descriptor.licence.verifiedBundledText(
                  in: licenceBundle,
              ) != nil
        else {
            throw RawCullAIModelDownloadError.missingVerifiedLicenceText(
                descriptor.displayName,
            )
        }

        var store = try load()
        store.acceptances.removeAll { $0.modelID == descriptor.id }
        store.acceptances.append(
            RawCullAIModelLicenceAcceptance(
                modelID: descriptor.id,
                modelVersion: descriptor.modelVersion,
                licenceName: descriptor.licence.name,
                licenceVersion: descriptor.licence.version,
                licenceTextSHA256: textSHA256,
                acceptedAt: .now,
                rawCullVersion: rawCullVersion,
            ),
        )
        store.acceptances.sort { $0.modelID.rawValue < $1.modelID.rawValue }

        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )
        let data = try JSONEncoder().encode(store)
        try data.write(to: fileURL, options: .atomic)
        cachedStore = store
    }

    private func load() throws -> Store {
        if let cachedStore {
            return cachedStore
        }

        let store: Store
        do {
            let data = try Data(contentsOf: fileURL)
            store = try JSONDecoder().decode(Store.self, from: data)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            store = Store(acceptances: [])
        }
        cachedStore = store
        return store
    }
}
