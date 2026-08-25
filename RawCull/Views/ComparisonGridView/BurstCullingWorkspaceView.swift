import RawCullCore
import SwiftUI

nonisolated enum BurstReviewKeyAction: Equatable {
    case previousImage
    case nextImage
    case nextGroup

    nonisolated static func resolve(characters: String?) -> BurstReviewKeyAction? {
        switch characters {
        case "p", "P": .previousImage
        case "n", "N": .nextImage
        case "g", "G": .nextGroup
        default: nil
        }
    }
}

nonisolated enum BurstFrameCachePolicy {
    static let capacity = 3

    static func indices(around selectedIndex: Int, itemCount: Int) -> [Int] {
        guard itemCount > 0, (0 ..< itemCount).contains(selectedIndex) else { return [] }
        let lowerBound = max(0, selectedIndex - 1)
        let upperBound = min(itemCount - 1, selectedIndex + 1)
        return Array(lowerBound ... upperBound)
    }
}

nonisolated struct BurstFrameCacheKey: Hashable {
    let fileID: FileItem.ID
    let source: ImagePreviewSource
}

struct BurstCullingWorkspaceView: View {
    @Bindable var viewModel: RawCullViewModel
    let groupID: Int
    let onCompare: () -> Void

    @State private var imageCache: [BurstFrameCacheKey: ComparisonImageState] = [:]
    @State private var viewportState = ComparisonViewportInteractionState()
    @State private var sourceSelection = ImageSourceSelectionState(initialSource: .embeddedJPG)
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider()

            VStack(spacing: 0) {
                imageStage
                Divider()
                filmstrip
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onAppear {
            isFocused = true
            selectFirstFileIfNeeded()
        }
        .onKeyPress(.leftArrow) { navigate(by: -1); return .handled }
        .onKeyPress(.rightArrow) { navigate(by: 1); return .handled }
        .onKeyPress(.escape) { viewModel.returnToActiveBurstGroupView(); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFaAxXpPnNgG012345tT")) { press in
            handleKeyPress(press.characters)
        }
        .task(id: imageLoadKey) {
            await loadSelectedImageWindow()
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            Task { await regenerateCachedFocusMasks() }
        }
        .onChange(of: groupID) { _, _ in
            imageCache = [:]
            viewportState = ComparisonViewportInteractionState()
            sourceSelection.resetForNewImage()
            selectFirstFileIfNeeded()
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 16) {
            Spacer()
            Text("\(viewModel.selectedSource?.name ?? "Catalog")  ·  Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")
                .font(.headline.monospaced())
                .foregroundStyle(.secondary)
            Spacer()

            Button {
                viewModel.returnToActiveBurstGroupView()
            } label: {
                Label("Burst list", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            reviewButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var reviewButton: some View {
        if isReviewed {
            reviewButtonContent
                .buttonStyle(.borderedProminent)
        } else {
            reviewButtonContent
                .buttonStyle(.bordered)
        }
    }

    private var reviewButtonContent: some View {
        Button {
            viewModel.toggleBurstGroupReviewed(groupID: groupID)
        } label: {
            Label(
                "Mark Reviewed",
                systemImage: isReviewed ? "checkmark.circle.fill" : "checkmark.circle",
            )
        }
        .controlSize(.large)
        .help(isReviewed ? "Unmark this burst as reviewed" : "Mark this burst as reviewed")
        .accessibilityValue(isReviewed ? "Selected" : "Not selected")
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
                    viewportState: $viewportState,
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

    private var filmstrip: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Burst \(burstNumber.formatted(.number.precision(.integerLength(2))))")
                Text("\(selectedIndex + 1) / \(files.count)")
            }
            .font(.callout.monospaced())
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .leading)

            ScrollViewReader { proxy in
                GeometryReader { geo in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(files) { file in
                                BurstFilmstripThumbnail(
                                    file: file,
                                    isSelected: file.id == viewModel.selectedFileID,
                                    isSuggested: analysis?.recommendedFileID == file.id,
                                    isDeferred: analysis?.reviewState == .deferred,
                                ) {
                                    viewModel.selectedFileID = file.id
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
                    .onAppear(perform: {
                        // Defer one run loop so LazyVStack IDs are registered in scroll geometry
                        DispatchQueue.main.async {
                            if let newID = viewModel.selectedFile?.id {
                                withAnimation {
                                    proxy.scrollTo(newID, anchor: .center)
                                }
                            }
                        }
                    })
                    .onChange(of: viewModel.selectedFileID) { _, newID in
                        guard let newID else { return }
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                navigationButton(systemImage: "chevron.left", delta: -1)
                navigationButton(systemImage: "chevron.right", delta: 1)
            }
        }
        .padding(16)
        .frame(height: 144)
        .background(.quaternary.opacity(0.28))
    }

    private func tagStrip(for file: FileItem) -> some View {
        HStack(spacing: 8) {
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
        guard let group = viewModel.similarityModel.burstGroups.first(where: { $0.id == groupID }) else { return [] }
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

    private var isReviewed: Bool {
        analysis?.reviewState == .reviewed
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
        (viewModel.similarityModel.burstGroups.firstIndex { $0.id == groupID } ?? groupID) + 1
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
        guard let destination = navigationDestination(by: delta) else { return }
        viewportState.offset = .zero
        viewportState.lastOffset = .zero
        sourceSelection.resetForNewImage()
        viewModel.selectedFileID = destination.id
    }

    private func applyRating(_ rating: Int) {
        guard let selectedFile else { return }
        viewModel.updateRatingAndAdvance(for: selectedFile, rating: rating, in: files)
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
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
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
        let windowFiles = BurstFrameCachePolicy.indices(
            around: selectedIndex,
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

        for file in loadOrder {
            await analyzeFocusIfNeeded(for: file, source: source)
            guard !Task.isCancelled else { return }
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
              !state.isFocusAnalysisComplete
        else { return }

        let analyzedState = await ComparisonGridImageCoordinator.analyzeFocus(
            for: file,
            state: state,
            viewModel: viewModel,
        )
        guard !Task.isCancelled else { return }
        guard imageCache[key] != nil else { return }
        imageCache[key] = analyzedState
    }

    private func regenerateCachedFocusMasks() async {
        let source = sourceSelection.selected
        let filesByID = Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0) })
        let cachedFiles = imageCache.keys.compactMap { key -> FileItem? in
            guard key.source == source else { return nil }
            return filesByID[key.fileID]
        }

        for file in cachedFiles {
            let key = cacheKey(for: file, source: source)
            imageCache[key]?.focusMask = nil
            imageCache[key]?.sharpnessBreakdown = nil
            imageCache[key]?.isFocusAnalysisComplete = false
        }

        for file in cachedFiles {
            await analyzeFocusIfNeeded(for: file, source: source)
            guard !Task.isCancelled else { return }
        }
    }

    private func cacheKey(
        for file: FileItem,
        source: ImagePreviewSource,
    ) -> BurstFrameCacheKey {
        BurstFrameCacheKey(fileID: file.id, source: source)
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
                viewportState.scale = min(5.0, viewportState.scale + 0.4)
                viewportState.lastScale = viewportState.scale
            }

        case .zoomOut:
            withAnimation(.spring()) {
                viewportState.scale = max(0.5, viewportState.scale - 0.4)
                viewportState.lastScale = viewportState.scale
            }

        case .toggleEmbeddedJPG:
            sourceSelection.toggleExtractionSource(.embeddedJPG)

        case .toggleDevelopedRAW:
            sourceSelection.toggleExtractionSource(.developedRAW)

        case .toggleFocusMask:
            viewportState.showFocusMask.toggle()

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

private struct BurstEvidenceShelf: View {
    let file: FileItem
    let image: NSImage?
    let rating: RatingDisplay
    let rank: Int
    let frameCount: Int
    let sharpness: Float?
    let overallScore: Float?
    let exif: ExifSummary

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 16) {
                HStack(spacing: 9) {
                    Text(file.name)
                        .font(.callout.weight(.semibold).monospaced())
                        .lineLimit(1)

                    evidenceBadge("#\(rank) / \(frameCount)", color: .secondary)
                }

                Divider().frame(height: 34)

                VStack(alignment: .trailing, spacing: 3) {
                    scoreRow("Sharpness", value: sharpness)
                    scoreRow("Overall", value: overallScore)
                }
                .frame(minWidth: 108)

                HistogramView(nsImage: image, height: 42)
                    .frame(width: 110)
                    .accessibilityLabel("Luminance histogram")

                VStack(alignment: .trailing, spacing: 3) {
                    Text(exif.exposureParts.joined(separator: "   "))
                    Text(exif.gearParts.joined(separator: "   "))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.monospaced())
                .lineLimit(1)
                .frame(maxWidth: 560, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }

    private func scoreRow(_ title: String, value: Float?) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value.map(percent) ?? "—")
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.caption)
    }

    private func percent(_ value: Float) -> String {
        value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func evidenceBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold).monospaced())
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: .rect(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.45), lineWidth: 1)
            }
    }
}

private struct BurstFilmstripThumbnail: View {
    let file: FileItem
    let isSelected: Bool
    let isSuggested: Bool
    let isDeferred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ThumbnailImageView(file: file, targetSize: 180, style: .grid, showsShimmer: true)
                    .frame(width: 132, height: 82)
                    .clipped()
                    .overlay(alignment: .topTrailing) {
                        if isSuggested || isDeferred {
                            Circle()
                                .fill(isSuggested ? Color.green : Color.orange)
                                .frame(width: 9, height: 9)
                                .padding(7)
                        }
                    }
                Text(file.name)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
            }
            .frame(width: 132)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .compositingGroup()
        .clipShape(.rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(
                    isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                    lineWidth: isSelected ? 3 : 1,
                )
        }
    }
}

private struct WorkspaceTag: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: .rect(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).stroke(color.opacity(0.5), lineWidth: 1) }
    }
}
