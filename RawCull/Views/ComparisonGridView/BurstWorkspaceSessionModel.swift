import AppKit
import Observation
import RawCullCore

@MainActor
@Observable
final class BurstWorkspaceSessionModel {
    var imageCache: [BurstFrameCacheKey: ComparisonImageState] = [:]
    var viewportState = ComparisonViewportInteractionState()
    var sourceSelection = ImageSourceSelectionState(initialSource: .embeddedJPG)
    var showSubjectOutline = false
    var subjectOutline: CGImage?
    var subjectOutlineFileID: FileItem.ID?
    private(set) var focusConfigurationRevision = 0

    @ObservationIgnored var overlayKeyMonitor: Any?

    func cachedWindowIndices(selectedIndex: Int, itemCount: Int) -> [Int] {
        BurstFrameCachePolicy.indices(around: selectedIndex, itemCount: itemCount)
    }

    func navigate(
        by delta: Int,
        from currentIndex: Int,
        in files: [FileItem],
        using actions: any ImageReviewSelectionActing,
    ) -> Bool {
        guard ImageReviewFeaturePolicy.select(
            delta: delta,
            from: currentIndex,
            in: files,
            using: actions,
        ) else { return false }
        viewportState.offset = .zero
        viewportState.lastOffset = .zero
        sourceSelection.resetForNewImage()
        return true
    }

    func applyRating(
        _ rating: Int,
        to file: FileItem,
        in files: [FileItem],
        using actions: any ImageReviewRatingActing,
    ) {
        actions.updateRatingAndAdvance(for: file, rating: rating, in: files)
    }

    func ratingDisplay(
        for file: FileItem,
        using provider: any ImageReviewRatingProviding,
    ) -> RatingDisplay {
        ImageReviewFeaturePolicy.ratingDisplay(for: file, using: provider)
    }

    func invalidateFocusAnalysis() {
        for key in imageCache.keys {
            imageCache[key]?.focusMask = nil
            imageCache[key]?.isFocusAnalysisComplete = false
        }
        focusConfigurationRevision += 1
    }

    func resetForGroupChange() {
        showSubjectOutline = false
        subjectOutline = nil
        subjectOutlineFileID = nil
        imageCache = [:]
        viewportState = ComparisonViewportInteractionState()
        sourceSelection.resetForNewImage()
    }

    func cancel() {
        if let overlayKeyMonitor {
            NSEvent.removeMonitor(overlayKeyMonitor)
            self.overlayKeyMonitor = nil
        }
    }
}
