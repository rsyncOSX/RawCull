import SwiftUI

nonisolated enum LoupeImageKeyAction: Equatable {
    case zoomIn
    case zoomOut
    case toggleEmbeddedJPG
    case toggleDevelopedRAW
    case toggleFocusMask
    case toggleSubjectOutline
    case toggleFocusPoints
    case toggleMetadata
    case inspectActualPixels

    nonisolated static func resolve(characters: String?) -> LoupeImageKeyAction? {
        if let sharedAction = ImageReviewKeyboardPolicy.action(for: characters) {
            return switch sharedAction {
            case .zoomIn: .zoomIn
            case .zoomOut: .zoomOut
            case .toggleEmbeddedJPG: .toggleEmbeddedJPG
            case .toggleDevelopedRAW: .toggleDevelopedRAW
            case .toggleFocusMask: .toggleFocusMask
            case .toggleSubjectOutline: .toggleSubjectOutline
            case .toggleFocusPoints: .toggleFocusPoints
            case .rating: nil
            }
        }

        return switch characters {
        case "e", "E":
            .toggleMetadata

        case "z", "Z":
            .inspectActualPixels

        default:
            nil
        }
    }
}

struct LoupeMainImageView: View {
    @Environment(RawCullViewModel.self) private var viewModel
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session = LoupeSessionModel()

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
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

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let file else { return nil }
        return viewModel.deepAIReviewController.maskCandidate(for: file.id)
    }

    private var subjectOutlineTaskID: ImageReviewSubjectOutlineRequestContext {
        ImageReviewSubjectOutlineRequestContext(
            fileID: file?.id,
            prompt: subjectOutlineCandidate?.maskPromptUsed?.rawValue,
            isPresented: outlinePresentation.isPresented,
        )
    }

    var body: some View {
        ZStack {
            if let thumbnailSizePreview {
                VStack {
                    GeometryReader { geo in
                        ZStack {
                            // 1️⃣ Image FIRST (background)
                            LoupeImageContent(session: session, url: url, thumbnailSizePreview: thumbnailSizePreview)
                                .scaleEffect(viewModel.scale)
                                .offset(viewModel.offset)
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                                .gesture(
                                    MagnifyGesture()
                                        .onChanged { value in
                                            viewModel.scale = viewModel.lastScale * value.magnification
                                        }
                                        .onEnded { _ in
                                            viewModel.lastScale = viewModel.scale
                                        },
                                )

                                .simultaneousGesture(
                                    DragGesture()
                                        .onChanged { value in
                                            if viewModel.scale > 1.0 {
                                                viewModel.offset = CGSize(
                                                    width: viewModel.lastOffset.width + value.translation.width,
                                                    height: viewModel.lastOffset.height + value.translation.height,
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            viewModel.lastOffset = viewModel.offset
                                        },
                                )

                            // 2️⃣ Focus mask overlay

                            if focusPresentation.isPresented, let mask = focusPresentation.image {
                                ImageReviewRasterOverlay(image: Image(nsImage: mask), size: geo.size, kind: .focusMap)
                                    .scaleEffect(viewModel.scale)
                                    .offset(viewModel.offset)
                                    .transition(.opacity)
                            }

                            if outlinePresentation.isPresented, let subjectOutline = outlinePresentation.image {
                                ImageReviewRasterOverlay(image: Image(decorative: subjectOutline, scale: 1, orientation: .up), size: geo.size, kind: .subjectOutline)
                                    .scaleEffect(viewModel.scale)
                                    .offset(viewModel.offset)
                                    .transition(.opacity)
                            }

                            // 3️⃣ Focus points overlay
                            if showFocusPoints, let focusPoints {
                                FocusOverlayView(
                                    focusPoints: focusPoints,
                                    imageSize: currentImageSize,
                                )
                                .scaleEffect(viewModel.scale)
                                .offset(viewModel.offset)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .blurReplace))
                            }

                            VStack {
                                Spacer()

                                ImageOverlayControlsView(
                                    showFocusMask: $focusPresentation.isPresented,
                                    focusMaskAvailable: currentDisplayedImage != nil,
                                    showSubjectOutline: $outlinePresentation.isPresented,
                                    showsSubjectOutlineControl: true,
                                    subjectOutlineAvailable: subjectOutlineCandidate != nil,
                                    subjectOutlineLoading: outlinePresentation.isLoading,
                                    hasFocusPoints: focusPoints != nil,
                                    showFocusPoints: $showFocusPoints,
                                    showShortcutHints: true,
                                    showImageSourceToggle: true,
                                    useThumbnailSource: useThumbnailSourceBinding,
                                    imageSourceSelection: Binding(
                                        get: { session.sourceSelection },
                                        set: { session.sourceSelection = $0 },
                                    ),
                                    imageSourceURL: file?.url,
                                    scale: viewModel.scale,
                                    canZoomOut: viewModel.scale > ImageReviewViewportPolicy.loupe.minimumScale,
                                    canZoomIn: viewModel.scale < ImageReviewViewportPolicy.loupe.maximumScale,
                                    canReset: viewModel.scale != 1.0 || viewModel.offset != .zero,
                                    onZoomOut: {
                                        withAnimation(.spring()) {
                                            viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: viewModel.scale)
                                            viewModel.lastScale = viewModel.scale
                                        }
                                    },
                                    onZoomReset: { withAnimation(.spring()) { viewModel.resetZoom() } },
                                    onZoomIn: {
                                        withAnimation(.spring()) {
                                            viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: viewModel.scale)
                                            viewModel.lastScale = viewModel.scale
                                        }
                                    },
                                )
                                .padding(.bottom, 12)
                            }

                            if let file {
                                LoupeMetadataOverlay(
                                    viewModel: viewModel, file: file, image: currentDisplayedImage,
                                    semanticSearchFeature: semanticSearchFeature,
                                )
                            }

                            if let failure = sourcePresentation.failure {
                                Text(failure.message)
                                    .font(.title2.weight(.semibold))
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                                    .background(.regularMaterial, in: Capsule())
                                    .transition(.opacity)
                            }
                        }
                        .focusable()
                        .focused($isImageFocused)
                        .focusEffectDisabled(true)
                        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFsSaAeEzZ")) { press in
                            handleKeyAction(LoupeImageKeyAction.resolve(characters: press.characters))
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
                  focusPresentation.isPresented else { return }
            generateFocusMaskIfNeeded()
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
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
        return session.thumbnailImage
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

    private var useThumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { session.sourceSelection.selected == .thumbnail },
            set: { session.selectSource($0 ? .thumbnail : .embeddedJPG) },
        )
    }

    private var sourcePresentation: ImageReviewSourcePresentation {
        session.sourcePresentation
    }

    private func handleKeyAction(_ action: LoupeImageKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }
        switch action {
        case .zoomIn:
            withAnimation(.spring()) {
                viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedIn(from: viewModel.scale)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .zoomOut:
            withAnimation(.spring()) {
                viewModel.scale = ImageReviewViewportPolicy.loupe.zoomedOut(from: viewModel.scale)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .toggleEmbeddedJPG:
            session.toggleSource(.embeddedJPG)
            return .handled

        case .toggleDevelopedRAW:
            session.toggleSource(.developedRAW)
            return .handled

        case .toggleFocusMask:
            focusPresentation.isPresented.toggle()
            return .handled

        case .toggleSubjectOutline:
            guard subjectOutlineCandidate != nil else { return .ignored }
            outlinePresentation.isPresented.toggle()
            return .handled

        case .toggleFocusPoints:
            showFocusPoints.toggle()
            return .handled

        case .toggleMetadata:
            withAnimation(.snappy) {
                viewModel.showsLoupeMetadataPanel.toggle()
            }
            return .handled

        case .inspectActualPixels:
            viewModel.openZoomOverlay(
                initialSource: .embeddedJPG,
                initialZoomMode: .actualPixels,
                showFocusPointsOnOpen: true,
            )
            return .handled
        }
    }

    /// The thumbnail list can retain focus while the Loupe image is visible.
    /// Match the zoom overlay's shortcut handling without intercepting text entry.
    private func installSubjectOutlineKeyMonitor() {
        subjectOutlineKeyMonitor.install { event in
            guard viewModel.mainViewMode == .loupe,
                  !viewModel.zoomOverlayVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  keyboardScope.accepts(event),
                  LoupeImageKeyAction.resolve(characters: event.characters) == .toggleSubjectOutline
            else { return .ignored }

            return handleKeyAction(.toggleSubjectOutline)
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
        let candidate = subjectOutlineCandidate
        await outlinePresentation.load {
            guard let file, let candidate else { return nil }
            let mask = await viewModel.deepAIReviewController.mask(for: candidate, in: [file])
            guard !Task.isCancelled, let mask else { return nil }
            return await DeepAIReviewMaskOutlineRenderer.outline(from: mask) ?? mask
        }
    }

    private func generateFocusMaskIfNeeded(delay: Duration? = nil) {
        guard let image = currentDisplayedImage else { return }
        let file = file
        var config = viewModel.sharpnessModel.effectiveFocusConfig
        if let file {
            config.iso = file.exifData?.isoValue ?? 400
            config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        }
        let model = viewModel.sharpnessModel.focusMaskModel
        let evidence = file.flatMap { viewModel.sharpnessModel.breakdowns[$0.id]?.focusEvidence }
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

struct LoupeImageContent: View {
    let session: LoupeSessionModel
    let url: URL
    let thumbnailSizePreview: Int

    var body: some View {
        @Bindable var session = session
        switch session.sourceSelection.selected {
        case .thumbnail:
            ThumbnailImageView(
                url: url,
                targetSize: thumbnailSizePreview,
                style: .list,
                showsShimmer: false,
                contentMode: .fit,
                image: $session.thumbnailImage,
            )

        case .embeddedJPG:
            if let embeddedJPGImage = session.embeddedJPGImage {
                Image(decorative: embeddedJPGImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else if session.isLoadingSource {
                ProgressView()
                    .fixedSize()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.title3)
                    Text("No extracted JPG")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }

        case .developedRAW:
            if let developedRAWImage = session.developedRAWImage {
                Image(decorative: developedRAWImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .fixedSize()
            }
        }
    }
}

struct LoupeMetadataOverlay: View {
    let viewModel: RawCullViewModel
    let file: FileItem
    let image: NSImage?
    let semanticSearchFeature: RawCullSemanticSearchFeature

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            CurrentRatingBadgeView(
                rating: ImageReviewFeaturePolicy.ratingDisplay(for: file, using: viewModel),
                density: .compact,
            )

            if viewModel.showsLoupeMetadataPanel {
                ZoomMetadataPanel(
                    file: file,
                    image: image,
                    cullingMetadata: ZoomCullingMetadata.make(
                        for: file,
                        viewModel: viewModel,
                        semanticSearchFeature: semanticSearchFeature,
                    ),
                    onHide: {
                        withAnimation(.snappy) {
                            viewModel.showsLoupeMetadataPanel = false
                        }
                    },
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(8)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topTrailing,
        )
    }
}
