import Foundation
import RawCullCore

/// Narrow repository boundary for the derived burst cache. Disk work remains
/// actor-isolated in `BurstAnalysisCache`; this main-actor adapter keeps the
/// coordinator independently replaceable in tests.
@MainActor
protocol BurstAnalysisCacheRepository: AnyObject {
    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot?

    func loadMigrationCandidate(catalog: URL) async -> BurstAnalysisCacheSnapshot?
    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async
    func delete(catalog: URL) async
}

@MainActor
final class LiveBurstAnalysisCacheRepository: BurstAnalysisCacheRepository {
    private let cache: BurstAnalysisCache

    init(cache: BurstAnalysisCache = .shared) {
        self.cache = cache
    }

    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: thumbnailMaxPixelSize,
            sharpnessSignature: sharpnessSignature,
            similaritySignature: similaritySignature,
        )
    }

    func loadMigrationCandidate(catalog: URL) async -> BurstAnalysisCacheSnapshot? {
        await cache.loadMigrationCandidate(catalog: catalog)
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        await cache.save(snapshot, catalog: catalog)
    }

    func delete(catalog: URL) async {
        await cache.delete(catalog: catalog)
    }
}
