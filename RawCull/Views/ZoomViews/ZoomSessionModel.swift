import AppKit
import Observation

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
