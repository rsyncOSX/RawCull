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
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "j", "J":
            .toggleEmbeddedJPG

        case "r", "R":
            .toggleDevelopedRAW

        case "f", "F":
            .toggleFocusMask

        case "s", "S":
            .toggleSubjectOutline

        case "a", "A":
            .toggleFocusPoints

        case "e", "E":
            .toggleMetadata

        case "z", "Z":
            .inspectActualPixels

        default:
            nil
        }
    }
}

struct MainThumbnailImageView: View {
    @Environment(RawCullViewModel.self) private var viewModel

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    private struct SubjectOutlineTaskID: Hashable {
        let fileID: UUID?
        let prompt: String?
        let isPresented: Bool
    }

    let url: URL
    let file: FileItem?
    let semanticSearchFeature: RawCullSemanticSearchFeature

    @State private var image: NSImage?
    @State private var thumbnailSizePreview: Int?
    @State private var sourceSelection = ImageSourceSelectionState()
    @State private var embeddedJPGImage: CGImage?
    @State private var developedRAWImage: CGImage?
    @State private var isLoadingSource = false
    @State private var sourceTask: Task<Void, Never>?
    @State private var showRAWNotSupported = false
    @State private var rawMessageTask: Task<Void, Never>?

    @State private var showFocusPoints = false

    // Focus mask state
    @State private var focusMask: NSImage?
    @State private var showFocusMask: Bool = false
    @State private var isGeneratingFocusMask = false
    @State private var focusMaskSourceURL: URL?
    @State private var focusMaskPreviewSource: ImagePreviewSource?
    @State private var maskTask: Task<Void, Never>?
    @State private var subjectOutline: CGImage?
    @State private var showSubjectOutline = false
    @State private var isLoadingSubjectOutline = false
    @FocusState private var isImageFocused: Bool

    private var subjectOutlineCandidate: DeepAIReviewCandidate? {
        guard let file else { return nil }
        return viewModel.deepAIReviewController.maskCandidate(for: file.id)
    }

    private var subjectOutlineTaskID: SubjectOutlineTaskID {
        SubjectOutlineTaskID(
            fileID: file?.id,
            prompt: subjectOutlineCandidate?.maskPromptUsed?.rawValue,
            isPresented: showSubjectOutline,
        )
    }

    var body: some View {
        ZStack {
            if let thumbnailSizePreview {
                VStack {
                    GeometryReader { geo in
                        ZStack {
                            // 1️⃣ Image FIRST (background)
                            displayedImageContent(thumbnailSizePreview: thumbnailSizePreview)
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

                            if showFocusMask, let mask = focusMask {
                                Image(nsImage: mask)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .scaleEffect(viewModel.scale)
                                    .offset(viewModel.offset)
                                    .blendMode(.screen)
                                    .opacity(0.95)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }

                            if showSubjectOutline, let subjectOutline {
                                Image(decorative: subjectOutline, scale: 1, orientation: .up)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .scaleEffect(viewModel.scale)
                                    .offset(viewModel.offset)
                                    .colorMultiply(.orange)
                                    .blendMode(.screen)
                                    .opacity(0.95)
                                    .allowsHitTesting(false)
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
                                    showFocusMask: $showFocusMask,
                                    focusMaskAvailable: currentDisplayedImage != nil,
                                    showSubjectOutline: $showSubjectOutline,
                                    showsSubjectOutlineControl: true,
                                    subjectOutlineAvailable: subjectOutlineCandidate != nil,
                                    subjectOutlineLoading: isLoadingSubjectOutline,
                                    hasFocusPoints: focusPoints != nil,
                                    showFocusPoints: $showFocusPoints,
                                    showShortcutHints: true,
                                    showImageSourceToggle: true,
                                    useThumbnailSource: useThumbnailSourceBinding,
                                    imageSourceSelection: $sourceSelection,
                                    scale: viewModel.scale,
                                    canZoomOut: viewModel.scale > 0.5,
                                    canZoomIn: viewModel.scale < 4.0,
                                    canReset: viewModel.scale != 1.0 || viewModel.offset != .zero,
                                    onZoomOut: {
                                        withAnimation(.spring()) {
                                            viewModel.scale = max(0.5, viewModel.scale - 0.2)
                                            viewModel.lastScale = viewModel.scale
                                        }
                                    },
                                    onZoomReset: { withAnimation(.spring()) { viewModel.resetZoom() } },
                                    onZoomIn: {
                                        withAnimation(.spring()) {
                                            viewModel.scale = min(4.0, viewModel.scale + 0.2)
                                            viewModel.lastScale = viewModel.scale
                                        }
                                    },
                                )
                                .padding(.bottom, 12)
                            }

                            if let file {
                                HStack(alignment: .top, spacing: 8) {
                                    CurrentRatingBadgeView(
                                        rating: ratingDisplay(for: file),
                                        density: .compact,
                                    )

                                    if viewModel.showsLoupeMetadataPanel {
                                        ZoomMetadataPanel(
                                            file: file,
                                            image: currentDisplayedImage,
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

                            if showRAWNotSupported {
                                Text("Not supported")
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
        .onChange(of: showFocusMask) { _, newValue in
            if newValue {
                generateFocusMaskIfNeeded()
            } else if isGeneratingFocusMask {
                maskTask?.cancel()
                maskTask = nil
                isGeneratingFocusMask = false
            }
        }
        .onChange(of: sourceSelection.selected) { _, _ in
            // Preserve the normalized mask while the same photo is redrawn.
            cancelFocusMaskGeneration()
            loadSelectedSourceIfNeeded()
        }
        .onChange(of: image) { _, newImage in
            guard newImage != nil,
                  sourceSelection.selected == .thumbnail,
                  showFocusMask else { return }
            generateFocusMaskIfNeeded()
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            maskTask?.cancel()
            focusMask = nil
            focusMaskSourceURL = nil
            focusMaskPreviewSource = nil
            guard showFocusMask else {
                isGeneratingFocusMask = false
                maskTask = nil
                return
            }
            maskTask = Task {
                isGeneratingFocusMask = true
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await regenerateMask(for: sourceSelection.selected)
                isGeneratingFocusMask = false
            }
        }
        .onChange(of: url) { _, _ in
            resetSourceImages()
            image = nil
            sourceSelection.resetForNewImage()
            clearRAWMessage()
            resetFocusMaskImage()
            loadSelectedSourceIfNeeded()
        }
        .onDisappear {
            maskTask?.cancel()
            maskTask = nil
            isGeneratingFocusMask = false
            sourceTask?.cancel()
            sourceTask = nil
            rawMessageTask?.cancel()
            rawMessageTask = nil
            isLoadingSource = false
        }
    }

    @ViewBuilder
    private func displayedImageContent(thumbnailSizePreview: Int) -> some View {
        switch sourceSelection.selected {
        case .thumbnail:
            ThumbnailImageView(
                url: url,
                targetSize: thumbnailSizePreview,
                style: .list,
                showsShimmer: false,
                contentMode: .fit,
                image: $image,
            )

        case .embeddedJPG:
            if let embeddedJPGImage {
                Image(decorative: embeddedJPGImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else if isLoadingSource {
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
            if let developedRAWImage {
                Image(decorative: developedRAWImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView()
                    .fixedSize()
            }
        }
    }

    private var currentDisplayedImage: NSImage? {
        if sourceSelection.selected == .embeddedJPG, let embeddedJPGImage {
            return NSImage(
                cgImage: embeddedJPGImage,
                size: NSSize(width: embeddedJPGImage.width, height: embeddedJPGImage.height),
            )
        }
        if sourceSelection.selected == .developedRAW, let developedRAWImage {
            return NSImage(cgImage: developedRAWImage, size: .zero)
        }
        return image
    }

    private var currentImageSize: NSSize? {
        if sourceSelection.selected == .embeddedJPG, let embeddedJPGImage {
            return NSSize(width: embeddedJPGImage.width, height: embeddedJPGImage.height)
        }
        if sourceSelection.selected == .developedRAW, let developedRAWImage {
            return NSSize(width: developedRAWImage.width, height: developedRAWImage.height)
        }
        return image?.size
    }

    private var useThumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { sourceSelection.selected == .thumbnail },
            set: { sourceSelection.select($0 ? .thumbnail : .embeddedJPG) },
        )
    }

    private func handleKeyAction(_ action: LoupeImageKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }
        switch action {
        case .zoomIn:
            withAnimation(.spring()) {
                viewModel.scale = min(4.0, viewModel.scale + 0.2)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .zoomOut:
            withAnimation(.spring()) {
                viewModel.scale = max(0.5, viewModel.scale - 0.2)
                viewModel.lastScale = viewModel.scale
            }
            return .handled

        case .toggleEmbeddedJPG:
            sourceSelection.toggleExtractionSource(.embeddedJPG)
            return .handled

        case .toggleDevelopedRAW:
            sourceSelection.toggleExtractionSource(.developedRAW)
            return .handled

        case .toggleFocusMask:
            showFocusMask.toggle()
            return .handled

        case .toggleSubjectOutline:
            guard subjectOutlineCandidate != nil else { return .ignored }
            showSubjectOutline.toggle()
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

    private func loadSelectedSourceIfNeeded() {
        sourceTask?.cancel()
        sourceTask = nil

        let requestedSource = sourceSelection.selected
        guard requestedSource != .thumbnail else {
            isLoadingSource = false
            if showFocusMask {
                generateFocusMaskIfNeeded()
            }
            return
        }
        if hasLoadedImage(for: requestedSource) {
            isLoadingSource = false
            if showFocusMask {
                generateFocusMaskIfNeeded()
            }
            return
        }

        isLoadingSource = true
        sourceTask = Task {
            do {
                let loadedImage: CGImage? = switch requestedSource {
                case .thumbnail:
                    nil

                case .embeddedJPG:
                    await ZoomPreviewHandler.loadExtractedJPGPreview(for: url)

                case .developedRAW:
                    try await ZoomPreviewHandler.loadDevelopedRAWPreview(for: url)
                }
                guard !Task.isCancelled, sourceSelection.selected == requestedSource else { return }
                if requestedSource == .embeddedJPG {
                    embeddedJPGImage = loadedImage
                } else {
                    developedRAWImage = loadedImage
                }
                isLoadingSource = false
                if showFocusMask {
                    generateFocusMaskIfNeeded()
                }
            } catch is CancellationError {
                return
            } catch {
                guard sourceSelection.selected == .developedRAW else { return }
                isLoadingSource = false
                sourceSelection.markDevelopedRAWUnavailable()
                showRAWFailureMessage()
            }
        }
    }

    private func hasLoadedImage(for source: ImagePreviewSource) -> Bool {
        switch source {
        case .thumbnail:
            image != nil

        case .embeddedJPG:
            embeddedJPGImage != nil

        case .developedRAW:
            developedRAWImage != nil
        }
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func loadSubjectOutline() async {
        subjectOutline = nil
        isLoadingSubjectOutline = false
        guard showSubjectOutline,
              let file,
              let candidate = subjectOutlineCandidate
        else { return }

        isLoadingSubjectOutline = true
        let mask = await viewModel.deepAIReviewController.mask(
            for: candidate,
            in: [file],
        )
        guard !Task.isCancelled else {
            isLoadingSubjectOutline = false
            return
        }
        if let mask {
            subjectOutline = await DeepAIReviewMaskOutlineRenderer.outline(from: mask) ?? mask
        }
        guard !Task.isCancelled else {
            subjectOutline = nil
            isLoadingSubjectOutline = false
            return
        }
        isLoadingSubjectOutline = false
    }

    // MARK: - Regenerate Mask

    private func generateFocusMaskIfNeeded() {
        let previewSource = sourceSelection.selected
        guard focusMaskSourceURL != url
            || focusMaskPreviewSource != previewSource
            || focusMask == nil
        else { return }
        guard currentDisplayedImage != nil, !isGeneratingFocusMask else { return }

        maskTask?.cancel()
        maskTask = Task {
            isGeneratingFocusMask = true
            await regenerateMask(for: previewSource)
            isGeneratingFocusMask = false
        }
    }

    private func regenerateMask(for requestedSource: ImagePreviewSource) async {
        guard let image = currentDisplayedImage else { return }
        let config = focusMaskConfig()
        let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
            from: image,
            scale: 1.0,
            configOverride: config,
            afPoint: file?.afFocusNormalized,
            iso: file?.exifData?.isoValue ?? 400,
            aperture: file?.exifData?.apertureValue,
            evidence: file.flatMap { viewModel.sharpnessModel.breakdowns[$0.id]?.focusEvidence },
        )
        guard !Task.isCancelled,
              sourceSelection.selected == requestedSource
        else { return }
        await MainActor.run {
            self.focusMask = mask
            self.focusMaskSourceURL = url
            self.focusMaskPreviewSource = requestedSource
        }
    }

    private func focusMaskConfig() -> FocusDetectorConfig {
        guard let file else { return viewModel.sharpnessModel.effectiveFocusConfig }
        var config = viewModel.sharpnessModel.effectiveFocusConfig
        config.iso = file.exifData?.isoValue ?? 400
        config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        return config
    }

    private func resetFocusMaskImage() {
        cancelFocusMaskGeneration()
        focusMask = nil
        focusMaskSourceURL = nil
        focusMaskPreviewSource = nil
    }

    private func cancelFocusMaskGeneration() {
        maskTask?.cancel()
        maskTask = nil
        isGeneratingFocusMask = false
    }

    private func resetSourceImages() {
        sourceTask?.cancel()
        sourceTask = nil
        embeddedJPGImage = nil
        developedRAWImage = nil
        isLoadingSource = false
    }

    private func showRAWFailureMessage() {
        rawMessageTask?.cancel()
        withAnimation { showRAWNotSupported = true }
        rawMessageTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            withAnimation { showRAWNotSupported = false }
        }
    }

    private func clearRAWMessage() {
        rawMessageTask?.cancel()
        rawMessageTask = nil
        showRAWNotSupported = false
    }
}
