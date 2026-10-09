import Foundation

nonisolated struct ReviewSelectedFile: Sendable {
    let id: UUID
    let url: URL
    let name: String
}

/// Native reads retain access until completion, including after catalog navigation.
@MainActor
final class ReviewCatalogSession {
    private let grants: [RawCullCatalogGrant]
    init(urls: [URL]) {
        grants = RawCullCatalogAccess.shared.retainAccess(for: urls)
    }

    @concurrent
    static func freeze(_ files: [ReviewSelectedFile]) async throws -> [ReviewFileSnapshot] {
        let grants = await RawCullCatalogAccess.shared.retainAccess(for: files.map(\.url))
        defer { withExtendedLifetime(grants) {} }
        return try files.map { file in
            try Task.checkCancellation()
            guard FileManager.default.isReadableFile(atPath: file.url.path) else { throw ReviewRunError.sourceUnavailable }
            return try ReviewFileSnapshot(id: ReviewImageID(rawValue: file.id.uuidString), fileID: file.id, url: file.url,
                                          displayName: file.name, fingerprint: ReviewFileSnapshot.fingerprint(file.url))
        }
    }

    @concurrent
    static func revalidate(_ files: [ReviewFileSnapshot]) async throws {
        let frozen = try await freeze(files.map { ReviewSelectedFile(id: $0.fileID, url: $0.url, name: $0.displayName) })
        guard frozen == files else { throw ReviewRunError.incompatible }
    }
}
