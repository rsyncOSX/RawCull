import AppKit
import Observation
import RawCullCore

@MainActor
@Observable
final class ZoomSessionModel {
    private var rawLoadID = UUID()
    private(set) var isLoadingRAWPreview = false

    func beginPreviewLoad(preservingImage: Bool) -> UUID? {
        guard !preservingImage || !isLoadingRAWPreview else { return nil }
        rawLoadID = UUID()
        isLoadingRAWPreview = sourceSelection.selected == .developedRAW
        return rawLoadID
    }

    func finishPreviewLoad(_ id: UUID) -> Bool {
        guard id == rawLoadID else { return false }
        isLoadingRAWPreview = false
        return true
    }

    var rawFitPreviewDimension = 2560
    var rawPreviewMaximumDimension: Int? {
        // Clipping/exposure inspection uses native samples, even while fitted to the window.
        evaluateRAWExposure || viewport.scale > 1 || pendingInitialZoomMode == .actualPixels ? nil : rawFitPreviewDimension
    }

    var focusMask: CGImage?
    var subjectOutline: CGImage?
    var viewport = ComparisonViewportInteractionState()
    var showSubjectOutline = false
    var isLoadingSubjectOutline = false
    var sourceSelection = ImageSourceSelectionState()
    var showsDevelopedRAWFailure = false
    var evaluateRAWExposure = false
    var rawExposureEV = 0.0
    var committedRAWExposureEV = 0.0
    var showRAWClippingWarning = false
    private struct RAWInspectionSnapshot {
        let source: ImageSourceSelectionState
        let exposureEV: Double
        let committedExposureEV: Double
        let clippingWarning: Bool
    }

    private var rawInspectionSnapshot: RAWInspectionSnapshot?

    func beginRAWExposureInspection() {
        guard !evaluateRAWExposure else { return }
        rawInspectionSnapshot = RAWInspectionSnapshot(
            source: sourceSelection,
            exposureEV: rawExposureEV,
            committedExposureEV: committedRAWExposureEV,
            clippingWarning: showRAWClippingWarning,
        )
        sourceSelection.select(.developedRAW)
        evaluateRAWExposure = true
    }

    func endRAWExposureInspection() {
        guard let snapshot = rawInspectionSnapshot else { return }
        evaluateRAWExposure = false
        sourceSelection = snapshot.source
        rawExposureEV = snapshot.exposureEV
        committedRAWExposureEV = snapshot.committedExposureEV
        showRAWClippingWarning = snapshot.clippingWarning
        rawInspectionSnapshot = nil
    }

    var pendingInitialZoomMode: ZoomOverlayInitialZoomMode?

    @ObservationIgnored var rawMessageTask: Task<Void, Never>?
    @ObservationIgnored var maskTask: Task<Void, Never>?
    @ObservationIgnored let keyMonitor = ReviewKeyMonitor()

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
        guard !evaluateRAWExposure else { return false }
        return ImageReviewFeaturePolicy.select(
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
        endRAWExposureInspection()
        rawExposureEV = 0
        committedRAWExposureEV = 0
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
        // Keep bounded completed previews for revisits, but release the active RAW graph on close.
        Task { @concurrent in
            await RAWPreviewRenderer.shared.releaseSource()
        }
        maskTask?.cancel()
        maskTask = nil
        rawMessageTask?.cancel()
        rawMessageTask = nil
        keyMonitor.remove()
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
