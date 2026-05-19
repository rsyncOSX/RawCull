import AppKit
import SwiftUI

struct ComparisonGridView: View {
    @Bindable var viewModel: RawCullViewModel

    @State private var imageStates: [FileItem.ID: ComparisonImageState] = [:]
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFocusMask = false
    @State private var showFocusPoints = false
    @State private var useThumbnailSource = false
    @State private var columnCount = 1
    @State private var keyMonitor: Any?
    @FocusState private var isFocused: Bool

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                if files.count > 1 {
                    ScrollView {
                        LazyVGrid(columns: columns(for: geo.size), spacing: 12) {
                            ForEach(files) { file in
                                ComparisonImagePaneView(
                                    file: file,
                                    state: imageStates[file.id],
                                    focusPoints: focusPoints(for: file),
                                    scale: scale,
                                    offset: offset,
                                    showFocusMask: showFocusMask,
                                    showFocusPoints: showFocusPoints,
                                    markerSize: viewModel.focusPointMarkerSize,
                                    isSelected: viewModel.selectedFileID == file.id,
                                    rating: ratingDisplay(for: file),
                                    zoomPanGesture: zoomPanGesture,
                                    onSelect: { viewModel.selectedFileID = file.id },
                                    onToggleZoom: toggleZoom,
                                )
                                .aspectRatio(3 / 2, contentMode: .fit)
                            }
                        }
                        .padding(12)

                        if let burstComparisonResult {
                            BurstComparisonEvidenceView(
                                result: burstComparisonResult,
                                onKeepBest: { viewModel.keepBestInGroup(from: files) },
                                onKeepTopTwo: { viewModel.keepTopTwoInGroup(from: files) },
                                onBack: viewModel.returnToActiveBurstGroupView,
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 90)
                        }
                    }

                    VStack {
                        Spacer()

                        VStack(spacing: 8) {
                            if let selectedComparisonFile {
                                RatingActionBarView(
                                    currentRating: ratingDisplay(for: selectedComparisonFile),
                                    onSelect: { rating in
                                        viewModel.updateRating(for: selectedComparisonFile, rating: rating)
                                    },
                                )
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                            }

                            ImageOverlayControlsView(
                                showFocusMask: $showFocusMask,
                                focusMaskAvailable: focusMaskAvailable,
                                hasFocusPoints: hasFocusPoints,
                                showFocusPoints: $showFocusPoints,
                                showShortcutHints: true,
                                showImageSourceToggle: true,
                                useThumbnailSource: $useThumbnailSource,
                                scale: scale,
                                canZoomOut: scale > 0.5,
                                canZoomIn: scale < 5.0,
                                canReset: scale != 1.0 || offset != .zero,
                                onZoomOut: decreaseZoom,
                                onZoomReset: { withAnimation(.spring()) { resetToFit() } },
                                onZoomIn: increaseZoom,
                            )
                        }
                        .padding(.bottom, 14)
                    }
                } else {
                    ContentUnavailableView(
                        "Select Images to Compare",
                        systemImage: "rectangle.split.2x1",
                        description: Text("Select two to four thumbnails in a grid view, then use Compare."),
                    )
                }
            }
        }
        .onGeometryChange(for: Int.self) { proxy in
            columnCount(for: proxy.size)
        } action: { newColumnCount in
            columnCount = newColumnCount
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigate(.left); return .handled }
        .onKeyPress(.rightArrow) { navigate(.right); return .handled }
        .onKeyPress(.upArrow) { navigate(.up); return .handled }
        .onKeyPress(.downArrow) { navigate(.down); return .handled }
        .onKeyPress(.escape) {
            if viewModel.activeBurstComparisonGroupID != nil {
                viewModel.returnToActiveBurstGroupView()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJxXpP012345tTfFaAbB")) { press in
            switch press.characters {
            case "+": increaseZoom(); return .handled
            case "-": decreaseZoom(); return .handled
            case "j", "J": useThumbnailSource.toggle(); return .handled
            case "f", "F": showFocusMask.toggle(); return .handled
            case "a", "A": showFocusPoints.toggle(); return .handled
            case "b", "B": return applyBurstKeepBest()
            case "x", "X": return applyRating(-1)
            case "p", "P", "0": return applyRating(0)
            case "1", "2": return applyRating(2)
            case "3": return applyRating(3)
            case "4": return applyRating(4)
            case "5": return applyRating(5)
            case "t", "T": return applyRating(3)
            default: return .ignored
            }
        }
        .onAppear {
            isFocused = true
            installKeyMonitor()
            resetToFit()
            selectFirstComparisonFileIfNeeded()
        }
        .onDisappear {
            removeKeyMonitor()
        }
        .task(id: loadKey) {
            selectFirstComparisonFileIfNeeded()
            await loadImages()
        }
        .onChange(of: viewModel.comparisonFileIDs) { _, _ in
            selectFirstComparisonFileIfNeeded()
        }
        .onChange(of: viewModel.sharpnessModel.focusMaskModel.config) { _, _ in
            Task {
                await regenerateFocusMasks()
            }
        }
    }

    private var files: [FileItem] {
        let selected = Set(viewModel.comparisonFileIDs)
        return viewModel.filteredFiles
            .filter { selected.contains($0.id) }
            .prefix(4)
            .map { $0 }
    }

    private var selectedComparisonFile: FileItem? {
        guard let selectedID = viewModel.selectedFileID else { return nil }
        return files.first { $0.id == selectedID }
    }

    private var burstComparisonResult: BurstAnalysisResult? {
        guard let groupID = viewModel.activeBurstComparisonGroupID else { return nil }
        return viewModel.burstAnalysisResult(for: groupID)
    }

    private var loadKey: String {
        let ids = files.map(\.id.uuidString).joined(separator: ",")
        return "\(ids)-\(useThumbnailSource)"
    }

    private var focusMaskAvailable: Bool {
        imageStates.values.contains { $0.focusMask != nil }
    }

    private var hasFocusPoints: Bool {
        files.contains { focusPoints(for: $0) != nil }
    }

    private var zoomPanGesture: AnyGesture<Void> {
        AnyGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { scale = lastScale * $0 }
                    .onEnded { _ in
                        lastScale = scale
                        if scale < 1.0 {
                            withAnimation(.spring()) { resetToFit() }
                        }
                    },
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height,
                            )
                        }
                    }
                    .onEnded { _ in lastOffset = offset },
            )
            .map { _ in () },
        )
    }

    private func columns(for size: CGSize) -> [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 320), spacing: 12),
            count: columnCount(for: size),
        )
    }

    private nonisolated func columnCount(for size: CGSize) -> Int {
        size.width >= 1200 ? 2 : 1
    }

    private func loadImages() async {
        let currentFiles = files
        imageStates = Dictionary(
            uniqueKeysWithValues: currentFiles.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: true))
            },
        )

        for file in currentFiles {
            guard !Task.isCancelled else { return }
            let (cgImage, nsImage) = await ComparisonImageLoader.loadImage(
                for: file,
                useThumbnailSource: useThumbnailSource,
            )
            guard !Task.isCancelled else { return }

            var state = ComparisonImageState(
                id: file.id,
                cgImage: cgImage,
                nsImage: nsImage,
                isLoading: false,
            )
            if let cgImage {
                let downscaled = cgImage.downscaled(toWidth: 1024)
                state.focusMask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
                    from: downscaled ?? cgImage,
                    scale: 1.0,
                )
            }
            imageStates[file.id] = state
        }
    }

    private func regenerateFocusMasks() async {
        for file in files {
            guard !Task.isCancelled else { return }
            guard let cgImage = imageStates[file.id]?.cgImage else { continue }
            let downscaled = cgImage.downscaled(toWidth: 1024)
            let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
                from: downscaled ?? cgImage,
                scale: 1.0,
            )
            guard !Task.isCancelled else { return }
            imageStates[file.id]?.focusMask = mask
        }
    }

    private func focusPoints(for file: FileItem) -> [FocusPoint]? {
        guard let points = viewModel.focusPoints?.filter({ $0.sourceFile == file.name }),
              points.count == 1 else { return nil }
        return points[0].focusPoints
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func selectFirstComparisonFileIfNeeded() {
        guard !files.isEmpty else { return }
        if let selectedID = viewModel.selectedFileID,
           files.contains(where: { $0.id == selectedID }) {
            return
        }
        viewModel.selectedFileID = files[0].id
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let file = selectedComparisonFile else { return .ignored }
        viewModel.updateRating(for: file, rating: rating)
        return .handled
    }

    private func applyBurstKeepBest() -> KeyPress.Result {
        guard viewModel.activeBurstComparisonGroupID != nil, !files.isEmpty else { return .ignored }
        viewModel.keepBestInGroup(from: files)
        return .handled
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.mainViewMode == .comparisonGrid,
                  !viewModel.zoomOverlayVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }

            return handleKeyEvent(event) == .handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> KeyPress.Result {
        switch event.keyCode {
        case 123:
            navigate(.left)
            return .handled

        case 124:
            navigate(.right)
            return .handled

        case 125:
            navigate(.down)
            return .handled

        case 126:
            navigate(.up)
            return .handled

        case 53:
            if viewModel.activeBurstComparisonGroupID != nil {
                viewModel.returnToActiveBurstGroupView()
                return .handled
            }
            return .ignored

        case 24:
            increaseZoom()
            return .handled

        case 27:
            decreaseZoom()
            return .handled

        case 38:
            useThumbnailSource.toggle()
            return .handled

        case 3:
            showFocusMask.toggle()
            return .handled

        case 0:
            showFocusPoints.toggle()
            return .handled

        case 11:
            return applyBurstKeepBest()

        case 7:
            return applyRating(-1)

        case 35, 29:
            return applyRating(0)

        case 18, 19:
            return applyRating(2)

        case 20:
            return applyRating(3)

        case 21:
            return applyRating(4)

        case 23:
            return applyRating(5)

        case 17:
            return applyRating(3)

        default:
            return .ignored
        }
    }

    private func navigate(_ direction: ComparisonGridNavigationDirection) {
        guard let selectedID = viewModel.selectedFileID,
              let currentIndex = files.firstIndex(where: { $0.id == selectedID }),
              let destinationIndex = ComparisonGridNavigation.destinationIndex(
                  from: currentIndex,
                  itemCount: files.count,
                  columnCount: columnCount,
                  direction: direction,
              )
        else { return }

        viewModel.selectedFileID = files[destinationIndex].id
    }

    private func toggleZoom() {
        withAnimation(.spring()) {
            scale > 1.0 ? resetToFit() : zoomToTarget()
        }
    }

    private func resetToFit() {
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func zoomToTarget() {
        scale = zoomLevel
        lastScale = zoomLevel
        offset = .zero
        lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            scale = min(5.0, scale + 0.4)
            lastScale = scale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            scale = max(0.5, scale - 0.4)
            lastScale = scale
        }
    }
}

private struct BurstComparisonEvidenceView: View {
    let result: BurstAnalysisResult
    let onKeepBest: () -> Void
    let onKeepTopTwo: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Burst \(result.groupID + 1) Comparison")
                    .font(.headline)
                Text(result.confidence.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Back To Group", action: onBack)
                    .controlSize(.small)
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence")
                        .font(.caption.weight(.semibold))
                    ForEach(result.reasons, id: \.self) { reason in
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Caution")
                        .font(.caption.weight(.semibold))
                    ForEach(result.cautions, id: \.self) { caution in
                        Text(caution)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    Button("Keep Best", action: onKeepBest)
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    Button("Keep Top 2", action: onKeepTopTwo)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
