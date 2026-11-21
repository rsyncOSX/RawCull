import SwiftUI

struct LoupeMainImageView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(WorkspacePresentationModel.self) private var presentation
    @Environment(ZoomOverlayModel.self) private var zoomOverlay
    @Environment(LoupeViewportModel.self) private var loupeViewport
    @Environment(WorkspaceNavigationModel.self) private var navigation
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @Environment(ReviewSubjectMasks.self) private var subjectMasks
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session = LoupeSessionModel()

    private var focusPoints: [FocusPoint]? {
        catalog.focusPoints(forFileWithID: selection.selectedFileID)
    }

    let url: URL
    let file: FileItem?
    let semanticSearchFeature: RawCullSemanticSearchFeature

    @State private var thumbnailSizePreview: Int?

    @State private var showFocusPoints = false

    @State private var focusPresentation = LoupeFocusPresentationModel()
    @State private var outlinePresentation = SubjectOutlinePresentationModel()
    @State private var subjectOutlineKeyMonitor = ReviewKeyMonitor()
    @FocusState private var isImageFocused: Bool

    private var subjectOutlineMask: ReviewSubjectMask? {
        file.flatMap(subjectMasks.mask)
    }

    private var subjectOutlineTaskID: ImageReviewSubjectOutlineRequestContext {
        ImageReviewSubjectOutlineRequestContext(
            fileID: file?.id,
            maskKey: subjectOutlineMask?.maskKey,
            isPresented: outlinePresentation.isPresented,
        )
    }

    var body: some View {
        @Bindable var viewport = loupeViewport
        ZStack {
            if let thumbnailSizePreview {
                VStack {
                    GeometryReader { geo in
                        LoupeImageStage(
                            session: session, url: url, thumbnailSizePreview: thumbnailSizePreview, size: geo.size,
                            scale: $viewport.scale, lastScale: $viewport.lastScale,
                            offset: $viewport.offset, lastOffset: $viewport.lastOffset,
                            showsFocusMask: focusPresentation.isPresented, focusMask: focusPresentation.image,
                            showsSubjectOutline: outlinePresentation.isPresented, subjectOutlineImage: outlinePresentation.image,
                            showFocusPoints: showFocusPoints, focusPoints: focusPoints,
                            currentImageSize: currentImageSize, sourceFailure: sourcePresentation.failure,
                        ) {
                            LoupeImageControls(
                                loupeViewport: loupeViewport, session: session, file: file,
                                showFocusMask: $focusPresentation.isPresented,
                                showSubjectOutline: $outlinePresentation.isPresented, showFocusPoints: $showFocusPoints,
                                focusMaskAvailable: currentDisplayedImage != nil, outlineAvailable: subjectOutlineMask != nil,
                                outlineIsLoading: outlinePresentation.isLoading, hasFocusPoints: focusPoints != nil,
                            )
                        } metadata: {
                            if let file {
                                LoupeMetadataOverlay(
                                    file: file, image: currentDisplayedImage,
                                    previewSource: session.sourceSelection.selected,
                                    semanticSearchFeature: semanticSearchFeature,
                                )
                            }
                        }
                        .focusable()
                        .focused($isImageFocused)
                        .focusEffectDisabled(true)
                        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFsSaAeEzZ")) { press in
                            keyboardController.handle(LoupeImageKeyAction.resolve(characters: press.characters))
                        }
                        .onAppear { isImageFocused = true }
                    }
                }
                .shadow(radius: 4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
            } else {
                ProgressView()
                    .fixedSize()
            }
        }
        .task {
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            thumbnailSizePreview = settingsmanager.thumbnailSizePreview
        }
        .task(id: subjectOutlineTaskID) {
            await loadSubjectOutline()
        }
        .background(ReviewKeyboardScopeReader(scope: keyboardScope))
        .onAppear {
            installSubjectOutlineKeyMonitor()
        }
        .onChange(of: focusPresentation.isPresented) { _, newValue in
            if newValue {
                generateFocusMaskIfNeeded()
            } else {
                focusPresentation.cancel()
            }
        }
        .onChange(of: session.sourceSelection.selected) { _, _ in
            // Preserve the normalized mask while the same photo is redrawn.
            focusPresentation.cancel()
            loadSelectedSourceIfNeeded()
        }
        .onChange(of: session.thumbnailImage) { _, newImage in
            guard newImage != nil,
                  session.sourceSelection.selected == .thumbnail,
                  focusPresentation.isPresented
            else { return }
            generateFocusMaskIfNeeded()
        }
        .onChange(of: sharpnessModel.effectiveFocusConfig) { _, _ in
            focusPresentation.reset()
            generateFocusMaskIfNeeded(delay: .milliseconds(400))
        }
        .onChange(of: url) { _, _ in
            installSubjectOutlineKeyMonitor()
            session.resetForNewImage()
            focusPresentation.reset()
            outlinePresentation.reset()
            loadSelectedSourceIfNeeded()
        }
        .onDisappear {
            removeSubjectOutlineKeyMonitor()
            focusPresentation.cancel()
            outlinePresentation.reset()
            session.cancel()
        }
    }

    private var currentDisplayedImage: NSImage? {
        if session.sourceSelection.selected == .embeddedJPG, let embeddedJPGImage = session.embeddedJPGImage {
            return NSImage(
                cgImage: embeddedJPGImage,
                size: NSSize(width: embeddedJPGImage.width, height: embeddedJPGImage.height),
            )
        }
        if session.sourceSelection.selected == .developedRAW, let developedRAWImage = session.developedRAWImage {
            return NSImage(cgImage: developedRAWImage, size: .zero)
        }
        return session.sourceSelection.selected == .thumbnail ? session.thumbnailImage : nil
    }

    private var currentImageSize: NSSize? {
        if session.sourceSelection.selected == .embeddedJPG, let embeddedJPGImage = session.embeddedJPGImage {
            return NSSize(width: embeddedJPGImage.width, height: embeddedJPGImage.height)
        }
        if session.sourceSelection.selected == .developedRAW, let developedRAWImage = session.developedRAWImage {
            return NSSize(width: developedRAWImage.width, height: developedRAWImage.height)
        }
        return session.thumbnailImage?.size
    }

    private var keyboardController: LoupeKeyboardController {
        LoupeKeyboardController(
            presentation: presentation, loupeViewport: loupeViewport,
            navigation: navigation, session: session,
            focusPresentation: focusPresentation, outlinePresentation: outlinePresentation,
            hasSubjectOutline: subjectOutlineMask != nil, showFocusPoints: $showFocusPoints,
        )
    }

    private var sourcePresentation: ImageReviewSourcePresentation {
        session.sourcePresentation
    }

    /// The thumbnail list can retain focus while the Loupe image is visible.
    /// Match the zoom overlay's shortcut handling without intercepting text entry.
    private func installSubjectOutlineKeyMonitor() {
        subjectOutlineKeyMonitor.install { event in
            guard navigation.mainViewMode == .loupe,
                  !zoomOverlay.isVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  keyboardScope.accepts(event),
                  LoupeImageKeyAction.resolve(characters: event.characters) == .toggleSubjectOutline
            else { return .ignored }

            return keyboardController.handle(.toggleSubjectOutline)
        }
    }

    private func removeSubjectOutlineKeyMonitor() {
        subjectOutlineKeyMonitor.remove()
    }

    private func loadSelectedSourceIfNeeded() {
        let requestedSource = session.sourceSelection.selected
        guard requestedSource != .thumbnail else {
            if focusPresentation.isPresented {
                generateFocusMaskIfNeeded()
            }
            return
        }
        if session.hasLoadedImage(for: requestedSource) {
            if focusPresentation.isPresented {
                generateFocusMaskIfNeeded()
            }
            return
        }

        session.beginSourceLoad { source in
            switch source {
            case .thumbnail:
                nil

            case .embeddedJPG:
                await ZoomPreviewHandler.loadExtractedJPGPreview(for: url)

            case .developedRAW:
                try await ZoomPreviewHandler.loadDevelopedRAWPreview(for: url)
            }
        }
    }

    private func loadSubjectOutline() async {
        let file = file
        let mask = subjectOutlineMask
        await outlinePresentation.load {
            guard let file, let mask else { return nil }
            return await ImageReviewSubjectOutlineLoader.load(
                file: file, mask: mask, masks: subjectMasks,
            )
        }
    }

    private func generateFocusMaskIfNeeded(delay: Duration? = nil) {
        guard let image = currentDisplayedImage else { return }
        let file = file
        var config = sharpnessModel.effectiveFocusConfig
        if let file {
            config.iso = file.exifData?.isoValue ?? 400
            config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        }
        let model = sharpnessModel.focusMaskModel
        let evidence = file.flatMap { sharpnessModel.breakdowns[$0.id]?.focusEvidence }
        focusPresentation.request(url: url, source: session.sourceSelection.selected, delay: delay) {
            await model.generateFocusMask(
                from: image, scale: 1.0, configOverride: config,
                afPoint: file?.afFocusNormalized,
                iso: file?.exifData?.isoValue ?? 400,
                aperture: file?.exifData?.apertureValue,
                evidence: evidence,
            )
        }
    }
}
