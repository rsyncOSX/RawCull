import AppKit
import Observation
import RawCullCore

@MainActor
@Observable
final class ZoomSessionModel {
    var focusMask: CGImage?
    var subjectOutline: CGImage?
    var viewport = ComparisonViewportInteractionState()
    var showSubjectOutline = false
    var isLoadingSubjectOutline = false
    var sourceSelection = ImageSourceSelectionState()
    var showsDevelopedRAWFailure = false
    var pendingInitialZoomMode: ZoomOverlayInitialZoomMode?

    @ObservationIgnored var rawMessageTask: Task<Void, Never>?
    @ObservationIgnored var maskTask: Task<Void, Never>?
    @ObservationIgnored var keyMonitor: Any?

    var sourcePresentation: ImageReviewSourcePresentation {
        ImageReviewSourcePresentation(
            selection: sourceSelection,
            showsDevelopedRAWFailure: showsDevelopedRAWFailure,
        )
    }

    func keyAction(
        characters: String?,
        keyCode: UInt16 = 0,
        navigationAxis: ZoomOverlayNavigationAxis,
    ) -> ZoomOverlayKeyAction? {
        ZoomOverlayKeyAction.resolve(
            characters: characters,
            keyCode: keyCode,
            navigationAxis: navigationAxis,
        )
    }

    func navigate(
        by delta: Int,
        from currentIndex: Int,
        in files: [FileItem],
        using actions: any ImageReviewSelectionActing,
    ) -> Bool {
        ImageReviewFeaturePolicy.select(
            delta: delta,
            from: currentIndex,
            in: files,
            using: actions,
        )
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

    func applyLaunchContext(_ context: ZoomOverlayLaunchContext, hasFocusTarget: Bool) {
        sourceSelection.select(context.initialSource)
        pendingInitialZoomMode = context.initialZoomMode
        if context.showFocusPointsOnOpen {
            viewport.showFocusPoints = hasFocusTarget
        }
    }

    func resetForSelectedFile(initialZoomMode: ZoomOverlayInitialZoomMode?) {
        maskTask?.cancel()
        maskTask = nil
        focusMask = nil
        subjectOutline = nil
        isLoadingSubjectOutline = false
        sourceSelection.resetForNewImage()
        clearRAWMessage()
        pendingInitialZoomMode = initialZoomMode
    }

    func cancel() {
        maskTask?.cancel()
        maskTask = nil
        rawMessageTask?.cancel()
        rawMessageTask = nil
        keyMonitor.map(NSEvent.removeMonitor)
        keyMonitor = nil
        focusMask = nil
        subjectOutline = nil
    }

    func showRAWFailureMessage() {
        rawMessageTask?.cancel()
        showsDevelopedRAWFailure = true
        rawMessageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.showsDevelopedRAWFailure = false
        }
    }

    func clearRAWMessage() {
        rawMessageTask?.cancel()
        rawMessageTask = nil
        showsDevelopedRAWFailure = false
    }
}
