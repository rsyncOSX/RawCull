import CoreGraphics
import Foundation

nonisolated struct ReviewSelectedFile: Equatable, Sendable {
    let id: UUID
    let url: URL
    let name: String
    var normalizedAFPoint: CGPoint?
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
        var frozen: [ReviewFileSnapshot] = []
        for file in files {
            try Task.checkCancellation()
            guard FileManager.default.isReadableFile(atPath: file.url.path) else { throw ReviewRunError.sourceUnavailable }
            let point: CGPoint? = if let recorded = file.normalizedAFPoint {
                recorded
            } else {
                await RawParserKitImageLoader.shared.fileMetadata(for: file.url)?.focusPoint
            }
            try Task.checkCancellation()
            try frozen.append(ReviewFileSnapshot(id: ReviewImageID(rawValue: file.id.uuidString), fileID: file.id, url: file.url,
                                                 displayName: file.name, fingerprint: ReviewFileSnapshot.fingerprint(file.url),
                                                 normalizedAFPoint: point.flatMap { point in
                                                     guard point.x.isFinite, point.y.isFinite,
                                                           (0 ... 1).contains(point.x), (0 ... 1).contains(point.y) else { return nil }
                                                     return point
                                                 }))
        }
        return frozen
    }

    @concurrent
    static func revalidate(_ files: [ReviewFileSnapshot]) async throws {
        let frozen = try await freeze(files.map { ReviewSelectedFile(id: $0.fileID, url: $0.url, name: $0.displayName, normalizedAFPoint: $0.normalizedAFPoint) })
        guard frozen == files else { throw ReviewRunError.incompatible }
    }
}
