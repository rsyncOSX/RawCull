import CoreGraphics
import Foundation
import Observation

/// The main subject mask Review found for a photo, used for the subject outline
/// (the S key) and the mask badge on thumbnails.
nonisolated struct ReviewSubjectMask: Hashable, Sendable {
    let url: URL
    let fingerprint: String
    let maskKey: String
    let concept: String
}

/// Subject masks from this session's Review results. Masks are matched to catalog
/// photos by location, and a mask is used only while the photo is unchanged on disk.
@Observable @MainActor
final class ReviewSubjectMasks {
    @ObservationIgnored private weak var feature: CombinedReviewFeature?

    init(feature: CombinedReviewFeature? = nil) {
        self.feature = feature
    }

    func bind(_ feature: CombinedReviewFeature) {
        self.feature = feature
    }

    /// The reviewed main subject for the photo, if a Review run produced one.
    func mask(for file: FileItem) -> ReviewSubjectMask? {
        let url = file.url.standardizedFileURL
        guard let result = feature?.displayedResults.last(where: { $0.file.url.standardizedFileURL == url }) else { return nil }
        return Self.mainSubjectMask(in: result)
    }

    /// The mask image, or nil when the photo changed after the review or the mask was cleared.
    func image(for mask: ReviewSubjectMask, file: FileItem) async -> CGImage? {
        guard let feature, file.url.standardizedFileURL == mask.url,
              ReviewFileSnapshot.currentFingerprint(file.url) == mask.fingerprint else { return nil }
        return await feature.exactInput(mask.maskKey)
    }

    /// The primary subject when Review assigned one, otherwise the most confident mask.
    nonisolated static func mainSubjectMask(in result: CombinedReviewResult) -> ReviewSubjectMask? {
        let usable = result.subjects.filter { $0.availability == .available && $0.maskInputReference != nil }
        let subject = usable.first { $0.relevance?.role == .primaryCandidate }
            ?? usable.max { $0.maskConfidence < $1.maskConfidence }
        guard let subject, let key = subject.maskInputReference else { return nil }
        return .init(
            url: result.file.url.standardizedFileURL,
            fingerprint: result.file.fingerprint,
            maskKey: key,
            concept: subject.concept,
        )
    }
}

extension ReviewFileSnapshot {
    /// The fingerprint of the file as it is now. URL caches resource values per
    /// instance, so the cache is cleared before reading.
    nonisolated static func currentFingerprint(_ url: URL) -> String? {
        var url = url
        url.removeAllCachedResourceValues()
        return try? fingerprint(url)
    }
}
