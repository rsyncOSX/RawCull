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

    private var keyboardController: BurstKeyboardController {
        BurstKeyboardController(
            viewModel: viewModel, session: session, groupID: groupID,
            selectedFile: selectedFile, hasImage: imageState?.cgImage != nil,
            navigate: navigate(by:), applyRating: applyRating,
        )
    }

    private var imageCoordinator: BurstWorkspaceImageCoordinator {
        BurstWorkspaceImageCoordinator(session: session, viewModel: viewModel)
    }

    private var imageCache: [BurstFrameCacheKey: ComparisonImageState] {
        get { session.imageCache }
        nonmutating set { session.imageCache = newValue }
    }

    private var viewportState: ComparisonViewportInteractionState {
        get { session.viewportState }
        nonmutating set { session.viewportState = newValue }
    }

    private var sourceSelection: ImageSourceSelectionState {
        get { session.sourceSelection }
        nonmutating set { session.sourceSelection = newValue }
    }

    private var showSubjectOutline: Bool {
        get { session.showSubjectOutline }
        nonmutating set { session.showSubjectOutline = newValue }
    }

    private var subjectOutline: CGImage? {
        get { session.subjectOutline }
        nonmutating set { session.subjectOutline = newValue }
    }

    private var subjectOutlineFileID: FileItem.ID? {
        get { session.subjectOutlineFileID }
        nonmutating set { session.subjectOutlineFileID = newValue }
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
                BurstImageStage(
                    selectedFile: selectedFile, imageState: imageState,
                    focusPoints: selectedFile.flatMap(focusPoints(for:)),
                    viewportState: Binding(get: { viewportState }, set: { viewportState = $0 }),
                    useThumbnailSource: thumbnailSourceBinding,
                    rating: selectedFile.map(ratingDisplay(for:)) ?? .unrated,
                    ratingValue: selectedFile.map { viewModel.getRating(for: $0) } ?? 0,
                    metadataImage: metadataImage, rank: selectedIndex + 1, frameCount: files.count,
                    sharpness: selectedCandidate?.sharpnessComponent, overallScore: selectedCandidate?.overallScore,
                    showSubjectOutline: showSubjectOutline, subjectOutlineFileID: subjectOutlineFileID,
                    subjectOutline: subjectOutline,
                    isSuggested: selectedFile.map { analysis?.recommendedFileID == $0.id } ?? false,
                    subjectLabel: selectedFile.flatMap { viewModel.sharpnessModel.saliencyInfo[$0.id]?.subjectLabel },
                    canNavigatePrevious: navigationDestination(by: -1) != nil,
                    canNavigateNext: navigationDestination(by: 1) != nil,
                    navigate: navigate(by:), applyRating: applyRating,
                    sourceChanged: { sourceSelection.select(thumbnailSourceBinding.wrappedValue ? .thumbnail : .embeddedJPG) },
                )
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
        .onKeyPress(.leftArrow) {
            navigate(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            navigate(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            viewModel.returnToActiveBurstGroupView()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFsSaAxXpPnNgG012345tT")) { press in
            keyboardController.handle(press.characters)
        }
        .task(id: subjectOutlineTaskID) {
            await loadSubjectOutline()
        }
        .task(id: imageLoadKey) {
            await imageCoordinator.loadWindow(files: files, selectedFile: selectedFile, selectedIndex: selectedIndex)
        }
        .task(id: focusMaskTaskID) {
            guard viewportState.showFocusMask, let selectedFile else { return }
            await imageCoordinator.analyzeFocusIfNeeded(for: selectedFile, source: sourceSelection.selected)
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

    private var files: [FileItem] {
        if groupID == -1 {
            return viewModel.singleImageReviewFiles
        }
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
        return imageCache[BurstFrameCacheKey(fileID: selectedFile.id, source: sourceSelection.selected)]
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

    private func installOverlayKeyMonitor() {
        session.keyMonitor.install { event in
            guard !viewModel.zoomOverlayVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  keyboardScope.accepts(event),
                  let characters = event.characters,
                  ["s", "S", "f", "F"].contains(characters)
            else { return .ignored }
            return keyboardController.handle(characters)
        }
    }

    private func removeOverlayKeyMonitor() {
        session.keyMonitor.remove()
    }

    private func loadSubjectOutline() async {
        subjectOutline = nil
        subjectOutlineFileID = nil
        guard showSubjectOutline,
              let file = selectedFile,
              let candidate = viewModel.deepAIReviewController.maskCandidate(for: file.id)
        else { return }
        let outline = await ImageReviewSubjectOutlineLoader.load(
            file: file, candidate: candidate, controller: viewModel.deepAIReviewController,
        )
        guard !Task.isCancelled else { return }
        subjectOutline = outline
        subjectOutlineFileID = file.id
    }
}
