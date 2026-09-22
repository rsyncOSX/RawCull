import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
private final class ImageReviewFeatureActionsSpy: ImageReviewFeatureActions {
    var selectedFileID: FileItem.ID?
    var taggedNamesCache: Set<String> = []
    var ratings: [FileItem.ID: Int] = [:]
    private(set) var appliedRating: Int?

    func getRating(for file: FileItem) -> Int { ratings[file.id] ?? 0 }

    func updateRatingAndAdvance(for _: FileItem, rating: Int, in _: [FileItem]) {
        appliedRating = rating
    }
}

@MainActor
@Suite("Image review feature dependencies")
struct ImageReviewFeatureDependenciesTests {
    @Test
    func `selection policy uses only focused selection capability`() {
        let files = [Self.file("a"), Self.file("b")]
        let actions = ImageReviewFeatureActionsSpy()

        #expect(ImageReviewFeaturePolicy.select(
            delta: 1,
            from: 0,
            in: files,
            using: actions,
        ))
        #expect(actions.selectedFileID == files[1].id)
        #expect(!ImageReviewFeaturePolicy.select(
            delta: 1,
            from: 1,
            in: files,
            using: actions,
        ))
    }

    @Test
    func `rating presentation uses focused rating capability`() {
        let file = Self.file("picked")
        let actions = ImageReviewFeatureActionsSpy()
        actions.ratings[file.id] = 4
        actions.taggedNamesCache.insert(file.name)

        #expect(ImageReviewFeaturePolicy.ratingDisplay(for: file, using: actions) == .stars(4))
    }

    private static func file(_ name: String) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            name: name,
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )
    }
}
