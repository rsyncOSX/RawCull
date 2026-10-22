//
//  ZoomOverlayView.swift
//  RawCull
//
//  Full-window zoom overlay. Replaces the older separate zoom windows by
//  covering the main window in a ZStack above the normal content. Dismiss
//  via Escape, the close button, or a second double-tap.
//

import AppKit
import RawCullCore
import SwiftUI

struct ZoomOverlayView: View {
    @Bindable var viewModel: RawCullViewModel
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session = ZoomSessionModel()
    @State private var rawClippingOverlay: CGImage?

    private struct ClippingTaskID: Equatable {
        let imageID: ObjectIdentifier?
        let enabled: Bool
    }

    private var clippingTaskID: ClippingTaskID {
        ClippingTaskID(
            imageID: viewModel.zoomOverlayCGImage.map(ObjectIdentifier.init),
            enabled: session.sourceSelection.selected == .developedRAW && session.showRAWClippingWarning,
        )
    }

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    private struct FocusMaskTaskID: Hashable {
        let imageID: ObjectIdentifier?
        let source: ImagePreviewSource
        let fileID: FileItem.ID?
    }

    @FocusState private var isImageFocused: Bool

    private let zoomLevel: CGFloat = 2.0

    private var focusMaskTaskID: FocusMaskTaskID {
        FocusMaskTaskID(
            imageID: maskAnalysisImage.map(ObjectIdentifier.init),
            source: session.sourceSelection.selected,
            fileID: viewModel.selectedFile?.id,
        )
    }

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let fileID = viewModel.selectedFile?.id else { return nil }
        return viewModel.deepAIReviewController.maskCandidate(for: fileID)
    }

    private var subjectOutlineTaskID: ImageReviewSubjectOutlineRequestContext {
        ImageReviewSubjectOutlineRequestContext(
            fileID: viewModel.selectedFile?.id,
            prompt: subjectOutlineCandidate?.maskPromptUsed?.rawValue,
            isPresented: session.showSubjectOutline,
        )
    }

    private var maskAnalysisImage: CGImage? {
        ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: viewModel.zoomOverlayAnalysisCGImage,
            displayImage: viewModel.zoomOverlayCGImage,
        )
    }

    private var navigation: ZoomNavigationPresentation {
        ZoomNavigationPresentation(viewModel: viewModel)
    }

    private var keyboardController: ZoomKeyboardController {
        ZoomKeyboardController(
            session: session, hasSubjectOutline: subjectOutlineCandidate != nil,
            navigate: navigateSelection(by:), dismiss: dismiss,
            increaseZoom: increaseZoom, decreaseZoom: decreaseZoom, applyRating: applyRating,
        )
    }

    private var analysisCoordinator: ZoomOverlayAnalysisCoordinator {
        ZoomOverlayAnalysisCoordinator(viewModel: viewModel, session: session)
    }

    private var sourcePresentation: ImageReviewSourcePresentation {
        session.sourcePresentation
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()

            ZoomImageCanvas(
                cgImage: viewModel.zoomOverlayCGImage, nsImage: viewModel.zoomOverlayNSImage,
                focusMask: session.focusMask, subjectOutline: session.subjectOutline,
                clippingOverlay: rawClippingOverlay, showsSubjectOutline: session.showSubjectOutline,
                focusTarget: focusTarget, viewport: $session.viewport,
                imageReady: applyPendingInitialZoomIfNeeded,
                resetToFit: resetToFit, zoomToTarget: zoomToTarget,
            )
            if let failure = sourcePresentation.failure {
                Text(failure.message)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.opacity)
            }

            VStack {
                ZoomOverlayChrome(
                    dimensions: viewModel.zoomOverlayCGImage.map { CGSize(width: $0.width, height: $0.height) }
                        ?? viewModel.zoomOverlayNSImage?.size,
                    rating: viewModel.selectedFile.map(ratingDisplay(for:)),
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                    isInspectingExposure: session.evaluateRAWExposure,
                    canNavigatePrevious: navigation.canNavigatePrevious, canNavigateNext: navigation.canNavigateNext,
                    navigate: navigateSelection(by:), dismiss: dismiss,
                )

                Spacer()

                ZoomOverlayControls(
                    viewModel: viewModel, session: session,
                    hasFocusTarget: focusTarget != nil,
                    onRate: { rating in _ = applyRating(rating) },
                    onZoomOut: decreaseZoom,
                    onZoomReset: { withAnimation(.spring()) { resetToFit() } },
                    onZoomIn: increaseZoom,
                )
            }

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .focusable()
        .focused($isImageFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 123,
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                ))
        }
        .onKeyPress(.rightArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 124,
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                ))
        }
        .onKeyPress(.upArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 126,
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                ))
        }
        .onKeyPress(.downArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 125,
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                ))
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFsSaAxXpP012345tT")) { press in
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: press.characters,
                    keyCode: 0,
                    navigationAxis: viewModel.zoomOverlayNavigationAxis,
                ))
        }
        .background(ReviewKeyboardScopeReader(scope: keyboardScope))
        .onAppear {
            isImageFocused = true
            installKeyMonitor()
            applyLaunchContext()
            reload()
        }
        .onDisappear {
            removeKeyMonitor()
            session.cancel()
        }
        .onChange(of: session.sourceSelection.selected) { _, _ in
            session.maskTask?.cancel()
            session.maskTask = nil
            // The mask is normalized to the same photo, so keep it visible
            // until analysis for the replacement preview completes.
            reload()
        }
        .onChange(of: session.evaluateRAWExposure) { _, _ in
            if session.sourceSelection.selected == .developedRAW {
                reload()
            }
        }
        .onChange(of: session.committedRAWExposureEV) { _, _ in
            if session.evaluateRAWExposure, session.sourceSelection.selected == .developedRAW {
                reload()
            }
        }
        .onChange(of: viewModel.selectedFile) { _, _ in
            guard viewModel.zoomOverlayVisible else { return }
            session.resetForSelectedFile(
                initialZoomMode: viewModel.zoomOverlayLaunchContext.initialZoomMode,
            )
            reload()
        }
        .task(id: focusMaskTaskID) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await analysisCoordinator.regenerateMaskFromCG()
        }
        .task(id: clippingTaskID) {
            rawClippingOverlay = nil
            guard clippingTaskID.enabled, let image = viewModel.zoomOverlayCGImage else { return }
            let overlay = await RAWPreviewClippingOverlay.make(from: image)
            guard !Task.isCancelled else { return }
            rawClippingOverlay = overlay
        }
        .task(id: subjectOutlineTaskID) {
            await analysisCoordinator.loadSubjectOutline()
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            session.maskTask?.cancel()
            session.maskTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await analysisCoordinator.regenerateMaskFromCG()
            }
        }
    }

    // MARK: - Reload

    private func applyLaunchContext() {
        let context = viewModel.zoomOverlayLaunchContext
        session.applyLaunchContext(context, hasFocusTarget: focusTarget != nil)
    }

    private func reload() {
        guard let file = viewModel.selectedFile else { return }
        viewModel.zoomExtractionTask?.cancel()
        viewModel.zoomExtractionTask = ZoomPreviewHandler.handleOverlay(
            file: file,
            source: session.sourceSelection.selected,
            viewModel: viewModel,
            evaluateExposure: session.evaluateRAWExposure,
            exposureEV: session.committedRAWExposureEV,
            onDevelopedRAWFailure: {
                session.sourceSelection.markDevelopedRAWUnavailable()
                showRAWFailureMessage()
            },
        )
    }

    private func navigateSelection(by delta: Int) {
        guard let currentZoomIndex = navigation.currentZoomIndex else { return }
        if session.navigate(
            by: delta,
            from: currentZoomIndex,
            in: navigation.orderedZoomFiles,
            using: viewModel,
        ) {
            prepareForNavigatedImage()
        }
    }

    private func installKeyMonitor() {
        session.keyMonitor.install { event in
            guard viewModel.zoomOverlayVisible,
                event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                keyboardScope.accepts(event)
            else { return .ignored }

            return handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        session.keyMonitor.remove()
    }

    private func handleKeyEvent(_ event: NSEvent) -> KeyPress.Result {
        keyboardController.handle(
            ZoomOverlayKeyAction.resolve(
                characters: event.characters,
                keyCode: event.keyCode,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let selectedFile = viewModel.selectedFile else { return .ignored }
        session.applyRating(rating, to: selectedFile, in: navigation.orderedZoomFiles, using: viewModel)
        return .handled
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        session.ratingDisplay(for: file, using: viewModel)
    }

    // MARK: - Dismiss

    private func dismiss() {
        if session.evaluateRAWExposure {
            session.endRAWExposureInspection()
            return
        }
        viewModel.closeZoomOverlay()
        resetToFit()
        session.focusMask = nil
        session.subjectOutline = nil
    }

    private func showRAWFailureMessage() {
        session.showRAWFailureMessage()
    }

    // MARK: - Mask regeneration

    // MARK: - Zoomable images

    // MARK: - Focus point overlay

    private var focusTarget: CGPoint? {
        if let point = focusPoints?.first {
            return CGPoint(x: point.normalizedX, y: point.normalizedY)
        }
        return viewModel.selectedFile?.afFocusNormalized
    }

    // MARK: - Toolbar button

    // MARK: - Zoom helpers

    private func resetToFit() {
        session.viewport.scale = 1.0
        session.viewport.lastScale = 1.0
        session.viewport.offset = .zero
        session.viewport.lastOffset = .zero
    }

    private func prepareForNavigatedImage() {
        session.viewport.offset = .zero
        session.viewport.lastOffset = .zero
        session.pendingInitialZoomMode = viewModel.zoomOverlayLaunchContext.initialZoomMode
    }

    private func zoomToTarget() {
        session.viewport.scale = zoomLevel
        session.viewport.lastScale = zoomLevel
        session.viewport.offset = .zero
        session.viewport.lastOffset = .zero
    }

    private func applyPendingInitialZoomIfNeeded(imageSize: CGSize, viewportSize: CGSize) {
        guard session.pendingInitialZoomMode == .actualPixels else { return }
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: focusTarget,
        )
        session.viewport.scale = transform.scale
        session.viewport.lastScale = transform.scale
        session.viewport.offset = transform.offset
        session.viewport.lastOffset = transform.offset
        session.pendingInitialZoomMode = nil
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            session.viewport.scale = ImageReviewViewportPolicy.comparison.zoomedIn(from: session.viewport.scale)
            session.viewport.lastScale = session.viewport.scale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            session.viewport.scale = ImageReviewViewportPolicy.comparison.zoomedOut(from: session.viewport.scale)
            session.viewport.lastScale = session.viewport.scale
        }
    }
}
