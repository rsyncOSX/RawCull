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
    @Environment(\.displayScale) private var displayScale
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(RatingsModel.self) private var ratings
    @Environment(ZoomOverlayModel.self) private var zoomOverlay
    @Environment(WorkspaceNavigationModel.self) private var workspaceNavigation
    @Environment(CatalogController.self) private var catalogController
    @Environment(CullingController.self) private var culling
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @Environment(DeepAIReviewController.self) private var deepAIReviewController
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session = ZoomSessionModel()
    @State private var rawClippingOverlay: CGImage?

    private struct ClippingTaskID: Equatable {
        let imageID: ObjectIdentifier?
        let enabled: Bool
    }

    private var clippingTaskID: ClippingTaskID {
        ClippingTaskID(
            imageID: zoomOverlay.cgImage.map(ObjectIdentifier.init),
            enabled: session.sourceSelection.selected == .developedRAW && session.showRAWClippingWarning,
        )
    }

    private var focusPoints: [FocusPoint]? {
        catalog.focusPoints(forFileWithID: selection.selectedFileID)
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
            fileID: catalogController.selectedFile?.id,
        )
    }

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let fileID = catalogController.selectedFile?.id else { return nil }
        return deepAIReviewController.maskCandidate(for: fileID)
    }

    private var subjectOutlineTaskID: ImageReviewSubjectOutlineRequestContext {
        ImageReviewSubjectOutlineRequestContext(
            fileID: catalogController.selectedFile?.id,
            prompt: subjectOutlineCandidate?.maskPromptUsed?.rawValue,
            isPresented: session.showSubjectOutline,
            maskStorageKey: subjectOutlineCandidate?.maskStorageKey,
        )
    }

    private var maskAnalysisImage: CGImage? {
        ZoomOverlayImagePolicy.analysisImage(
            dedicatedAnalysisImage: zoomOverlay.analysisCGImage,
            displayImage: zoomOverlay.cgImage,
        )
    }

    private var navigation: ZoomNavigationPresentation {
        ZoomNavigationPresentation(
            catalogController: catalogController, selection: selection,
        )
    }

    private var keyboardController: ZoomKeyboardController {
        ZoomKeyboardController(
            session: session, hasSubjectOutline: subjectOutlineCandidate != nil,
            navigate: navigateSelection(by:), dismiss: dismiss,
            increaseZoom: increaseZoom, decreaseZoom: decreaseZoom, applyRating: applyRating,
        )
    }

    private var analysisCoordinator: ZoomOverlayAnalysisCoordinator {
        ZoomOverlayAnalysisCoordinator(
            catalogController: catalogController,
            deepAIReviewController: deepAIReviewController,
            session: session,
        )
    }

    private var sourcePresentation: ImageReviewSourcePresentation {
        session.sourcePresentation
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()

            ZoomImageCanvas(
                cgImage: zoomOverlay.cgImage, nsImage: zoomOverlay.nsImage,
                nativeImageSize: zoomOverlay.nativeSize,
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
                    dimensions: zoomOverlay.nativeSize
                        ?? zoomOverlay.cgImage.map { CGSize(width: $0.width, height: $0.height) }
                        ?? zoomOverlay.nsImage?.size,
                    rating: catalogController.selectedFile.map(ratingDisplay(for:)),
                    isReducedRAWPreview: zoomOverlay.rawIsReduced,
                    rawRenderSeconds: zoomOverlay.rawRenderSeconds,
                    isPreparingRAW: session.isLoadingRAWPreview,
                    isPreparingRAWPreview: session.rawPreviewMaximumDimension != nil,
                    navigationAxis: zoomOverlay.navigationAxis,
                    isInspectingExposure: session.evaluateRAWExposure,
                    canNavigatePrevious: navigation.canNavigatePrevious, canNavigateNext: navigation.canNavigateNext,
                    navigate: navigateSelection(by:), dismiss: dismiss,
                )

                Spacer()

                ZoomOverlayControls(
                    zoomOverlay: zoomOverlay, catalogController: catalogController,
                    deepAIReviewController: deepAIReviewController,
                    session: session, hasFocusTarget: focusTarget != nil,
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
        .onGeometryChange(for: Int?.self) { [displayScale] geometry in
            RAWPreviewSizing.fitDimension(viewport: geometry.size, displayScale: displayScale)
        } action: { dimension in
            if let dimension {
                session.rawFitPreviewDimension = dimension
            }
        }
        .onChange(of: session.rawPreviewMaximumDimension) { _, _ in
            if session.sourceSelection.selected == .developedRAW {
                reload(preservingImage: true)
            }
        }
        .focusable()
        .focused($isImageFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 123,
                    navigationAxis: zoomOverlay.navigationAxis,
                ),
            )
        }
        .onKeyPress(.rightArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 124,
                    navigationAxis: zoomOverlay.navigationAxis,
                ),
            )
        }
        .onKeyPress(.upArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 126,
                    navigationAxis: zoomOverlay.navigationAxis,
                ),
            )
        }
        .onKeyPress(.downArrow) {
            keyboardController.handle(
                ZoomOverlayKeyAction.resolve(
                    characters: nil,
                    keyCode: 125,
                    navigationAxis: zoomOverlay.navigationAxis,
                ),
            )
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
                    navigationAxis: zoomOverlay.navigationAxis,
                ),
            )
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
        .onChange(of: catalogController.selectedFile) { _, _ in
            guard zoomOverlay.isVisible else { return }
            session.resetForSelectedFile(
                initialZoomMode: zoomOverlay.launchContext.initialZoomMode,
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
            guard clippingTaskID.enabled, let image = zoomOverlay.cgImage else { return }
            let overlay = await RAWPreviewClippingOverlay.make(from: image)
            guard !Task.isCancelled else { return }
            rawClippingOverlay = overlay
        }
        .task(id: subjectOutlineTaskID) {
            await analysisCoordinator.loadSubjectOutline()
        }
        .onChange(of: sharpnessModel.effectiveFocusConfig) { _, _ in
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
        let context = zoomOverlay.launchContext
        session.applyLaunchContext(context, hasFocusTarget: focusTarget != nil)
    }

    private func reload(preservingImage: Bool = false) {
        guard let file = catalogController.selectedFile else { return }
        // Finish the current image before following a resize; avoid cancelling every window pixel.
        guard let loadID = session.beginPreviewLoad(preservingImage: preservingImage) else { return }
        let dimension = session.rawPreviewMaximumDimension
        zoomOverlay.extractionTask?.cancel()
        zoomOverlay.extractionTask = ZoomPreviewHandler.handleOverlay(
            file: file,
            source: session.sourceSelection.selected,
            zoomOverlay: zoomOverlay,
            evaluateExposure: session.evaluateRAWExposure,
            exposureEV: session.committedRAWExposureEV,
            maximumDimension: dimension,
            preservingImage: preservingImage,
            onFinished: {
                guard session.finishPreviewLoad(loadID) else { return }
                if !Task.isCancelled, zoomOverlay.isVisible,
                   session.sourceSelection.selected == .developedRAW,
                   dimension != session.rawPreviewMaximumDimension {
                    reload(preservingImage: true)
                }
            },
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
            using: selection,
        ) {
            prepareForNavigatedImage()
        }
    }

    private func installKeyMonitor() {
        session.keyMonitor.install { event in
            guard zoomOverlay.isVisible,
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
                navigationAxis: zoomOverlay.navigationAxis,
            ),
        )
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let selectedFile = catalogController.selectedFile else { return .ignored }
        session.applyRating(rating, to: selectedFile, in: navigation.orderedZoomFiles, using: culling)
        return .handled
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        session.ratingDisplay(for: file, using: ratings)
    }

    // MARK: - Dismiss

    private func dismiss() {
        if session.evaluateRAWExposure {
            session.endRAWExposureInspection()
            return
        }
        workspaceNavigation.closeZoomOverlay()
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
        return catalogController.selectedFile?.afFocusNormalized
    }

    // MARK: - Toolbar button

    // MARK: - Zoom helpers

    private func resetToFit() {
        session.viewport.resetTransform()
    }

    private func prepareForNavigatedImage() {
        session.viewport.offset = .zero
        session.viewport.lastOffset = .zero
        session.pendingInitialZoomMode = zoomOverlay.launchContext.initialZoomMode
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
            session.viewport.zoomIn()
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            session.viewport.zoomOut()
        }
    }
}
