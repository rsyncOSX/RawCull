import Foundation

/// Experimental counterpart of policy 1 in Scripts/EvaluatePeopleRanking.py.
/// The caller must verify that every frame shows the same primary human face.
nonisolated enum PeopleRankingPreview {
    @concurrent
    static func candidateOrder(for urls: [URL]) async -> [URL]? {
        guard urls.count >= 2, Set(urls).count == urls.count else { return nil }
        let access = await RawCullCatalogAccess.shared.retainAccess(for: urls)
        defer { withExtendedLifetime(access) {} }
        let cache = FaceEvidenceCache()
        var previewSize: CGSize?
        var details: [Double] = []

        for url in urls {
            guard !Task.isCancelled else { return nil }
            let revision = BurstCloseUpIdentity.revision(url)
            guard let evidence = cache.load(for: url, signature: FaceEvidenceCache.signature(sourceRevision: revision)),
                  evidence.faces.count == 1,
                  let detail = evidence.faces.first?.localDetail, detail.isFinite, detail > 0,
                  BurstCloseUpIdentity.revision(url) == revision
            else { return nil }
            let size = CGSize(width: evidence.previewWidth, height: evidence.previewHeight)
            guard previewSize == nil || previewSize == size else { return nil }
            previewSize = size
            details.append(detail)
        }

        guard let peak = details.max() else { return nil }
        return urls.indices.sorted {
            let left = Double($0) - 1.5 * (details[$0] / peak)
            let right = Double($1) - 1.5 * (details[$1] / peak)
            return left == right ? $0 < $1 : left < right
        }.map { urls[$0] }
    }
}
