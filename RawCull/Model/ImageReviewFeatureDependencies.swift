import RawCullCore

@MainActor
protocol ImageReviewSelectionActing: AnyObject {
    var selectedFileID: FileItem.ID? { get set }
}

@MainActor
protocol ImageReviewRatingProviding: AnyObject {
    var taggedNamesCache: Set<String> { get }
    func getRating(for file: FileItem) -> Int
}

@MainActor
protocol ImageReviewRatingActing: AnyObject {
    func updateRatingAndAdvance(for file: FileItem, rating: Int, in orderedFiles: [FileItem])
}

@MainActor
protocol ImageReviewFeatureActions:
    ImageReviewSelectionActing,
    ImageReviewRatingProviding,
    ImageReviewRatingActing {}

extension RawCullViewModel: ImageReviewFeatureActions {}

@MainActor
enum ImageReviewFeaturePolicy {
    static func ratingDisplay(
        for file: FileItem,
        using provider: any ImageReviewRatingProviding,
    ) -> RatingDisplay {
        RatingDisplay(
            rating: provider.getRating(for: file),
            isExplicit: provider.taggedNamesCache.contains(file.name),
        )
    }

    static func select(
        delta: Int,
        from currentIndex: Int,
        in files: [FileItem],
        using selection: any ImageReviewSelectionActing,
    ) -> Bool {
        let destination = currentIndex + delta
        guard files.indices.contains(destination) else { return false }
        selection.selectedFileID = files[destination].id
        return true
    }
}
