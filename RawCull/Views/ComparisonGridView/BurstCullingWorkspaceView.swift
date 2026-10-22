import OSLog
import RawCullCore
import SwiftUI

struct BurstCullingWorkspaceView: View {
    @Bindable var viewModel: RawCullViewModel
    let groupID: Int
    let onCompare: () -> Void
    @State private var keyboardScope = ReviewKeyboardScope()
    @State private var session = BurstWorkspaceSessionModel()

    @FocusState private var isFocused: Bool

    private var imageCache: [BurstFrameCacheKey: ComparisonImageState] {
        get { session.imageCache } nonmutating set { session.imageCache = newValue }
    }

    private var viewportState: ComparisonViewportInteractionState {
        get { session.viewportState } nonmutating set { session.viewportState = newValue }
    }

    private var sourceSelection: ImageSourceSelectionState {
        get { session.sourceSelection } nonmutating set { session.sourceSelection = newValue }
    }

    private var showSubjectOutline: Bool {
        get { session.showSubjectOutline } nonmutating set { session.showSubjectOutline = newValue }
    }

    private var subjectOutline: CGImage? {
        get { session.subjectOutline } nonmutating set { session.subjectOutline = newValue }
    }

    private var subjectOutlineFileID: FileItem.ID? {
        get { session.subjectOutlineFileID } nonmutating set { session.subjectOutlineFileID = newValue }
    }

    private var overlayKeyMonitor: Any? {
        get { session.overlayKeyMonitor } nonmutating set { session.overlayKeyMonitor = newValue }
    }

    private var focusConfigurationRevision: Int {
        session.focusConfigurationRevision
    }

    private var subjectOutlineTaskID: ImageReviewSubjectOutlineRequestContext {
        ImageReviewSubjectOutlineRequestContext(
            fileID: selectedFile?.id,
            prompt: selectedFile.flatMap {
                viewModel.deepAIReviewController.maskCandidate(for: $0.id)?.maskPromptUsed?.rawValue
            },
            isPresented: showSubjectOutline,
        )
    }

    private struct FocusMaskTaskID: Hashable {
        let imageKey: String
        let hasImage: Bool
        let isPresented: Bool
        let configurationRevision: Int
    }

    private var focusMaskTaskID: FocusMaskTaskID {
        FocusMaskTaskID(
            imageKey: imageLoadKey,
            hasImage: imageState?.cgImage != nil,
            isPresented: viewportState.showFocusMask,
            configurationRevision: focusConfigurationRevision,
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            BurstWorkspaceHeader(viewModel: viewModel, groupID: groupID)
            Divider()

            VStack(spacing: 0) {
                imageStage
                Divider()
                BurstWorkspaceFilmstrip(
                    viewModel: viewModel, files: files, analysis: analysis, burstNumber: burstNumber, isSingleImages: groupID == -1,
                    canNavigatePrevious: navigationDestination(by: -1) != nil,
                    canNavigateNext: navigationDestination(by: 1) != nil,
                    navigate: navigate,
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .background(ReviewKeyboardScopeReader(scope: keyboardScope))
        .onAppear {
            isFocused = true
            selectFirstFileIfNeeded()
            installOverlayKeyMonitor()
        }
        .onDisappear { session.cancel() }
        .onKeyPress(.leftArrow) { navigate(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigate(by: 1); return .handled }
        .onKeyPress(.escape) { viewModel.returnToActiveBurstGroupView(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFsSaAxXpPnNgG012345tT")) { press in
            handleKeyPress(press.characters)
        }
        .task(id: subjectOutlineTaskID) {
            await loadSubjectOutline()
        }
        .task(id: imageLoadKey) {
            await loadSelectedImageWindow()
        }
        .task(id: focusMaskTaskID) {
            guard viewportState.showFocusMask, let selectedFile else { return }
            await analyzeFocusIfNeeded(for: selectedFile, source: sourceSelection.selected)
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            session.invalidateFocusAnalysis()
        }
        .onChange(of: groupID) { _, _ in
            installOverlayKeyMonitor()
            session.resetForGroupChange()
            selectFirstFileIfNeeded()
        }
    }

    private var shortcutGuide: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                shortcut("P/N", action: "frame")
                separator
                shortcut("G", action: "next group")
                separator
                shortcut("+/−", action: "zoom")
                separator
                shortcut("2–5", action: "rate")
                separator
                shortcut("0", action: "pick")
                separator
                shortcut("X", action: "reject")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.regularMaterial, in: .rect(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.white.opacity(0.12), lineWidth: 1)
            }
        }
        .scrollIndicators(.hidden)
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Keyboard shortcuts: P or N changes frame, G opens the next group, plus or minus zooms, 2 through 5 rates, 0 picks, and X rejects")
    }

    private var imageStage: some View {
        ZStack {
            Color.black.opacity(0.2)

            if let selectedFile {
                ComparisonImagePaneView(
                    file: selectedFile,
                    state: imageState,
                    focusPoints: focusPoints(for: selectedFile),
                    viewportState: Binding(get: { viewportState }, set: { viewportState = $0 }),
                    useThumbnailSource: thumbnailSourceBinding,
                    isSelected: true,
                    rating: ratingDisplay(for: selectedFile),
                    exifSummary: ExifSummary.make(from: selectedFile.exifData),
                    saliencyLabel: nil,
                    burstAnalysis: nil,
                    burstCandidate: nil,
                    burstRating: viewModel.getRating(for: selectedFile),
                    sharpnessContext: nil,
                    onSelect: {},
                    onRate: applyRating,
                    onSourceChange: {
                        sourceSelection.select(thumbnailSourceBinding.wrappedValue ? .thumbnail : .embeddedJPG)
                    },
                    showsChrome: false,
                    allowsDoubleClickZoom: false,
                    subjectOutline: showSubjectOutline && subjectOutlineFileID == selectedFile.id
                        ? subjectOutline : nil,
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 82)
                .padding(.top, 36)
                .padding(.bottom, 2)
            } else {
                ContentUnavailableView("No burst frame", systemImage: "photo")
            }

            if let selectedFile {
                VStack(spacing: 0) {
                    BurstEvidenceShelf(
                        file: selectedFile,
                        image: metadataImage,
                        rating: ratingDisplay(for: selectedFile),
                        rank: selectedIndex + 1,
                        frameCount: files.count,
                        sharpness: selectedCandidate?.sharpnessComponent,
                        overallScore: selectedCandidate?.overallScore,
                        exif: ExifSummary.make(from: selectedFile.exifData),
                    )
                    .padding(.top, 12)
                    Spacer()
                    shortcutGuide
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 116)
                .allowsHitTesting(true)
            }

            if let selectedFile {
                tagStrip(for: selectedFile)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(18)
                    .allowsHitTesting(false)
            }

            HStack {
                navigationButton(systemImage: "chevron.left", delta: -1)
                Spacer()
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
            .padding(.horizontal, 24)
        }
        .frame(minHeight: 420)
    }

    private func tagStrip(for file: FileItem) -> some View {
        HStack(spacing: 8) {
            if let image = imageState?.cgImage {
                ImagePixelDimensionsBadgeView(width: image.width, height: image.height)
            }

            let rating = RatingDisplay(
                rating: viewModel.getRating(for: file),
                isExplicit: viewModel.taggedNamesCache.contains(file.name),
            )
            WorkspaceTag(title: rating.label, color: rating.color)

            if analysis?.recommendedFileID == file.id {
                WorkspaceTag(title: "Suggested", color: .orange)
            }

            if let subject = viewModel.sharpnessModel.saliencyInfo[file.id]?.subjectLabel {
                WorkspaceTag(title: subject, color: .cyan)
            }
        }
    }

    private func shortcut(_ key: String, action: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
            Text(action)
        }
    }

    private var separator: some View {
        Text("·")
            .accessibilityHidden(true)
    }

    private func navigationButton(systemImage: String, delta: Int) -> some View {
        Button { navigate(by: delta) } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .disabled(navigationDestination(by: delta) == nil)
    }

    private var files: [FileItem] {
        if groupID == -1 { return viewModel.singleImageReviewFiles }
        guard let group = viewModel.similarityFeature.burstGroups.first(where: { $0.id == groupID }) else { return [] }
        let filesByID = Dictionary(
            uniqueKeysWithValues: viewModel.activeCatalogFiles.map { ($0.id, $0) },
        )
        let rankedIDs = analysis?.candidates.map(\.fileID) ?? group.fileIDs
        return rankedIDs.compactMap { filesByID[$0] }
    }

    private var analysis: BurstAnalysisResult? {
        viewModel.burstAnalysisResult(for: groupID)
    }

    private var selectedCandidate: BurstCandidateScore? {
        guard let selectedFile else { return nil }
        return analysis?.candidates.first { $0.fileID == selectedFile.id }
    }

    private var selectedFile: FileItem? {
        guard let selectedID = viewModel.selectedFileID else { return files.first }
        return files.first { $0.id == selectedID } ?? files.first
    }

    private var imageState: ComparisonImageState? {
        guard let selectedFile else { return nil }
        return imageCache[cacheKey(for: selectedFile, source: sourceSelection.selected)]
    }

    private var metadataImage: NSImage? {
        if let nsImage = imageState?.nsImage {
            return nsImage
        }
        guard let cgImage = imageState?.cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }

    private var selectedIndex: Int {
        guard let selectedFile else { return 0 }
        return files.firstIndex { $0.id == selectedFile.id } ?? 0
    }

    private var burstNumber: Int {
        (viewModel.similarityFeature.burstGroups.firstIndex { $0.id == groupID } ?? groupID) + 1
    }

    private func selectFirstFileIfNeeded() {
        guard !files.isEmpty else { return }
        if let selectedID = viewModel.selectedFileID, files.contains(where: { $0.id == selectedID }) {
            return
        }
        viewModel.selectedFileID = files[0].id
    }

    private func navigationDestination(by delta: Int) -> FileItem? {
        let destination = selectedIndex + delta
        guard files.indices.contains(destination) else { return nil }
        return files[destination]
    }

    private func navigate(by delta: Int) {
        _ = session.navigate(
            by: delta,
            from: selectedIndex,
            in: files,
            using: viewModel,
        )
    }

    private func applyRating(_ rating: Int) {
        guard let selectedFile else { return }
        session.applyRating(rating, to: selectedFile, in: files, using: viewModel)
    }

    private var imageLoadKey: String {
        "\(selectedFile?.id.description ?? "none")|\(sourceTitle)"
    }

    private var sourceTitle: String {
        switch sourceSelection.selected {
        case .thumbnail: "thumbnail"
        case .embeddedJPG: "jpg"
        case .developedRAW: "raw"
        }
    }

    private var thumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { sourceSelection.selected == .thumbnail },
            set: { sourceSelection.select($0 ? .thumbnail : .embeddedJPG) },
        )
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        session.ratingDisplay(for: file, using: viewModel)
    }

    private func focusPoints(for file: FileItem) -> [FocusPoint]? {
        guard let points = viewModel.focusPoints?.first(where: { $0.sourceFile == file.name }) else { return nil }
        return points.focusPoints
    }

    private func loadSelectedImageWindow() async {
        guard let selectedFile else {
            imageCache = [:]
            return
        }

        let source = sourceSelection.selected
        let windowFiles = session.cachedWindowIndices(
            selectedIndex: selectedIndex,
            itemCount: files.count,
        ).map { files[$0] }
        let retainedKeys = Set(windowFiles.map { cacheKey(for: $0, source: source) })
        imageCache = imageCache.filter { retainedKeys.contains($0.key) }

        let loadOrder = [selectedFile] + windowFiles.filter { $0.id != selectedFile.id }
        for file in loadOrder {
            let loaded = await ensureDecodedImage(
                for: file,
                source: source,
                reportsDevelopedRAWFailure: file.id == selectedFile.id,
            )
            guard !Task.isCancelled else { return }
            if file.id == selectedFile.id, !loaded {
                return
            }
        }
    }

    private func ensureDecodedImage(
        for file: FileItem,
        source: ImagePreviewSource,
        reportsDevelopedRAWFailure: Bool,
    ) async -> Bool {
        let key = cacheKey(for: file, source: source)
        if let state = imageCache[key], !state.isLoading {
            return true
        }

        imageCache[key] = ComparisonImageState(id: file.id, isLoading: true)

        let decodedState: ComparisonImageState
        switch source {
        case .thumbnail, .embeddedJPG:
            decodedState = await ComparisonGridImageCoordinator.loadDecodedState(
                for: file,
                useThumbnailSource: source == .thumbnail,
            )

        case .developedRAW:
            do {
                let image = try await ZoomPreviewHandler.loadDevelopedRAWPreview(for: file.url)
                decodedState = ComparisonImageState(id: file.id, cgImage: image)
            } catch is CancellationError {
                return false
            } catch {
                guard !Task.isCancelled else { return false }
                imageCache.removeValue(forKey: key)
                if reportsDevelopedRAWFailure {
                    sourceSelection.markDevelopedRAWUnavailable()
                }
                return false
            }
        }

        guard !Task.isCancelled else { return false }
        imageCache[key] = decodedState
        return true
    }

    private func analyzeFocusIfNeeded(
        for file: FileItem,
        source: ImagePreviewSource,
    ) async {
        let key = cacheKey(for: file, source: source)
        guard let state = imageCache[key],
              !state.isLoading,
              state.cgImage != nil,
              state.focusMask == nil
        else { return }

        Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice("Generating focus mask")
        let analyzedState = await ComparisonGridImageCoordinator.analyzeFocus(
            for: file,
            state: state,
            viewModel: viewModel,
        )
        guard !Task.isCancelled, imageCache[key] != nil else { return }
        Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice("Mask returned: \(analyzedState.focusMask != nil)")
        imageCache[key] = analyzedState
    }

    private func cacheKey(
        for file: FileItem,
        source: ImagePreviewSource,
    ) -> BurstFrameCacheKey {
        BurstFrameCacheKey(fileID: file.id, source: source)
    }

    private func installOverlayKeyMonitor() {
        removeOverlayKeyMonitor()
        overlayKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !viewModel.zoomOverlayVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  keyboardScope.accepts(event),
                  let characters = event.characters,
                  ["s", "S", "f", "F"].contains(characters)
            else { return event }
            return handleKeyPress(characters) == .handled ? nil : event
        }
    }

    private func removeOverlayKeyMonitor() {
        if let overlayKeyMonitor {
            NSEvent.removeMonitor(overlayKeyMonitor)
            self.overlayKeyMonitor = nil
        }
    }

    private func loadSubjectOutline() async {
        subjectOutline = nil
        subjectOutlineFileID = nil
        guard showSubjectOutline,
              let file = selectedFile,
              let candidate = viewModel.deepAIReviewController.maskCandidate(for: file.id), let mask = await viewModel.deepAIReviewController.mask(for: candidate, in: [file]),
              !Task.isCancelled else { return }
        let outline = await DeepAIReviewMaskOutlineRenderer.outline(from: mask) ?? mask
        guard !Task.isCancelled else { return }
        subjectOutline = outline
        subjectOutlineFileID = file.id
    }

    private func handleKeyAction(_ action: ZoomOverlayKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }

        switch action {
        case .navigatePrevious:
            navigate(by: -1)

        case .navigateNext:
            navigate(by: 1)

        case .escape:
            viewModel.returnToActiveBurstGroupView()

        case .zoomIn:
            withAnimation(.spring()) {
                viewportState.scale = ImageReviewViewportPolicy.comparison.zoomedIn(from: viewportState.scale)
                viewportState.lastScale = viewportState.scale
            }

        case .zoomOut:
            withAnimation(.spring()) {
                viewportState.scale = ImageReviewViewportPolicy.comparison.zoomedOut(from: viewportState.scale)
                viewportState.lastScale = viewportState.scale
            }

        case .toggleEmbeddedJPG:
            sourceSelection.toggleExtractionSource(.embeddedJPG)

        case .toggleDevelopedRAW:
            sourceSelection.toggleExtractionSource(.developedRAW)

        case .toggleFocusMask:
            viewportState.showFocusMask.toggle()
            Logger(subsystem: "RawCull", category: "BurstFocusDebug").notice("Toggle focus: \(viewportState.showFocusMask), image: \(imageState?.cgImage != nil)")

        case .toggleSubjectOutline:
            guard let selectedFile,
                  viewModel.deepAIReviewController.maskCandidate(for: selectedFile.id) != nil
            else { return .ignored }
            showSubjectOutline.toggle()

        case .toggleFocusPoints:
            viewportState.showFocusPoints.toggle()

        case let .rating(rating):
            applyRating(rating)
        }
        return .handled
    }

    private func handleKeyPress(_ characters: String) -> KeyPress.Result {
        if let action = BurstReviewKeyAction.resolve(characters: characters) {
            switch action {
            case .previousImage:
                navigate(by: -1)

            case .nextImage:
                navigate(by: 1)

            case .nextGroup:
                viewModel.advanceToNextBurstGroup(after: groupID)
            }
            return .handled
        }

        return handleKeyAction(ZoomOverlayKeyAction.resolve(
            characters: characters,
            keyCode: 0,
            navigationAxis: .horizontal,
        ))
    }
}
