import Foundation

/// Experimental counterpart of policy 1 in Scripts/EvaluatePeopleRanking.py.
/// The caller must verify that every frame shows the same primary human face.
nonisolated enum PeopleRankingPreview {
    @concurrent
    static func candidateOrder(for urls: [URL], cache: FaceEvidenceCache = FaceEvidenceCache()) async -> [URL]? {
        guard urls.count >= 2, Set(urls).count == urls.count else { return nil }
        let access = await RawCullCatalogAccess.shared.retainAccess(for: urls)
        defer { withExtendedLifetime(access) {} }
        var previewSize: CGSize?
        var details: [Double] = []
        var faceSizes: [CGSize] = []

        for url in urls {
            guard !Task.isCancelled else { return nil }
            let revision = BurstCloseUpIdentity.revision(url)
            guard let evidence = cache.load(for: url, signature: FaceEvidenceCache.signature(sourceRevision: revision)),
                  evidence.faces.count == 1,
                  let face = evidence.faces.first,
                  let detail = face.localDetail, detail.isFinite, detail > 0,
                  BurstCloseUpIdentity.revision(url) == revision
            else { return nil }
            let size = CGSize(width: evidence.previewWidth, height: evidence.previewHeight)
            guard previewSize == nil || previewSize == size else { return nil }
            previewSize = size
            details.append(detail)
            faceSizes.append(face.normalizedBounds.size)
        }

        guard comparableFaceSizes(faceSizes) else { return nil }
        return rankedIndices(details: details).map { urls[$0] }
    }

    /// Compare the full range so a gradual change across a burst is also rejected.
    static func comparableFaceSizes(_ sizes: [CGSize]) -> Bool {
        // Initial experimental tolerance, pending evaluation on labeled bursts.
        let maximumRatio = 1.25
        for dimensions in [sizes.map(\.width), sizes.map(\.height)] {
            guard dimensions.allSatisfy({ $0.isFinite && $0 > 0 }),
                  let smallest = dimensions.min(), let largest = dimensions.max(),
                  largest <= smallest * maximumRatio
            else { return false }
        }
        return true
    }

    static func rankedIndices(details: [Double]) -> [Int] {
        guard let peak = details.max() else { return [] }
        return details.indices.sorted {
            let left = Double($0) - 1.5 * (details[$0] / peak)
            let right = Double($1) - 1.5 * (details[$1] / peak)
            return left == right ? $0 < $1 : left < right
        }
    }
}
