import Foundation
import PhotoAnalysisKit

/// Experimental counterpart of policy 1 in Scripts/EvaluatePeopleRanking.py.
/// The caller must verify that every frame shows the same primary human face.
nonisolated enum PeopleRankingPreview {
    enum Failure: LocalizedError {
        case tooFewFrames
        case previewUnavailable(String)
        case noFace(String)
        case multipleFaces(String)
        case detailUnavailable(String)
        case previewSizesDiffer
        case faceSizesDiffer

        var errorDescription: String? {
            switch self {
            case .tooFewFrames: String(localized: "Choose a burst with two or more images.")
            case let .previewUnavailable(name): String(localized: "Could not check the face in \(name).")
            case let .noFace(name): String(localized: "No face detected in \(name).")
            case let .multipleFaces(name): String(localized: "Multiple faces detected in \(name).")
            case let .detailUnavailable(name): String(localized: "Face detail unavailable in \(name).")
            case .previewSizesDiffer: String(localized: "Embedded preview sizes differ across this burst.")
            case .faceSizesDiffer: String(localized: "Face sizes vary too much across this burst.")
            }
        }
    }

    @concurrent
    static func candidateOrder(for urls: [URL], cache: FaceEvidenceCache = FaceEvidenceCache()) async -> [URL]? {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: urls)
        defer { withExtendedLifetime(access) {} }
        return try? await rank(urls) { url in
            let revision = BurstCloseUpIdentity.revision(url)
            guard let evidence = cache.load(for: url, signature: FaceEvidenceCache.signature(sourceRevision: revision)),
                  BurstCloseUpIdentity.revision(url) == revision
            else { throw Failure.previewUnavailable(url.lastPathComponent) }
            return evidence
        }
    }

    @concurrent
    static func analyzeAndRank(_ urls: [URL], progress: @MainActor @Sendable (Int) -> Void) async throws -> [URL] {
        try await rank(urls, progress: progress) { url in
            try await BurstDetectedFaceLoader.shared.evidence(for: url)
        }
    }

    private static func rank(
        _ urls: [URL],
        progress: @MainActor @Sendable (Int) -> Void = { _ in },
        evidence load: (URL) async throws -> FaceEvidenceResult,
    ) async throws -> [URL] {
        guard urls.count >= 2, Set(urls).count == urls.count else { throw Failure.tooFewFrames }
        var previewSize: CGSize?
        var details: [Double] = []
        var faceSizes: [CGSize] = []

        for (index, url) in urls.enumerated() {
            try Task.checkCancellation()
            await progress(index + 1)
            let name = url.lastPathComponent
            let evidence: FaceEvidenceResult
            do {
                evidence = try await load(url)
            } catch {
                try Task.checkCancellation()
                throw Failure.previewUnavailable(name)
            }
            guard let face = evidence.faces.first else { throw Failure.noFace(name) }
            guard evidence.faces.count == 1 else { throw Failure.multipleFaces(name) }
            guard let detail = face.localDetail, detail.isFinite, detail > 0 else {
                throw Failure.detailUnavailable(name)
            }
            let size = CGSize(width: evidence.previewWidth, height: evidence.previewHeight)
            guard previewSize == nil || previewSize == size else { throw Failure.previewSizesDiffer }
            previewSize = size
            details.append(detail)
            faceSizes.append(face.normalizedBounds.size)
        }

        try Task.checkCancellation()
        guard comparableFaceSizes(faceSizes) else { throw Failure.faceSizesDiffer }
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
