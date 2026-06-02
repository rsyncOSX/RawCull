import AppKit
import SwiftUI

struct ComparisonGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var showCandidateInspector: Bool

    @State private var imageStates: [FileItem.ID: ComparisonImageState] = [:]
    @State private var interactionStates: [FileItem.ID: ComparisonPaneInteractionState] = [:]
    @State private var finalistFocusActive = false
    @State private var keyMonitor: Any?
    @State private var scrollPositionID: FileItem.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if files.count > 1 {
                VStack(spacing: 0) {
                    if let burstComparisonResult {
                        BurstComparisonEvidenceView(
                            result: burstComparisonResult,
                            selectedFile: selectedComparisonFile,
                            canApplyOneClickCulling: canApplyOneClickCulling,
                            onKeepBest: { viewModel.keepBestInGroup(from: allComparisonFiles) },
                            onKeepTopTwo: { viewModel.keepTopTwoInGroup(from: allComparisonFiles) },
                            finalistFocusActive: finalistFocusActive,
                            onInspectFinalists: inspectFinalists,
                            onShowAll: showAllCandidates,
                            onSetManualWinner: { file in
                                viewModel.setManualBurstWinner(file, in: allComparisonFiles)
                            },
                            onBack: viewModel.returnToActiveBurstGroupView,
                        )
                        .padding(.horizontal, 12)
                    }

                    GeometryReader { geometry in
                        ScrollView(.horizontal) {
                            LazyHStack(spacing: 0) {
                                ForEach(files) { file in
                                    let burstAnalysis = burstComparisonResult
                                    ComparisonImagePaneView(
                                        file: file,
                                        state: imageStates[file.id],
                                        focusPoints: focusPoints(for: file),
                                        interactionState: interactionBinding(for: file),
                                        markerSize: viewModel.focusPointMarkerSize,
                                        isSelected: viewModel.selectedFileID == file.id,
                                        rating: ratingDisplay(for: file),
                                        exifSummary: ExifSummary.make(from: file.exifData),
                                        saliencyLabel: saliencyLabel(for: file),
                                        burstAnalysis: burstAnalysis,
                                        burstCandidate: burstCandidate(for: file, in: burstAnalysis),
                                        burstRating: viewModel.getRating(for: file),
                                        sharpnessContext: sharpnessContext(for: file),
                                        inspectorIsPresented: showCandidateInspector,
                                        onSelect: { viewModel.selectedFileID = file.id },
                                        onRate: { rating in
                                            viewModel.updateRating(for: file, rating: rating)
                                        },
                                        onToggleInspector: {
                                            showCandidateInspector.toggle()
                                        },
                                        onSourceChange: {
                                            Task {
                                                await reloadImage(for: file)
                                            }
                                        },
                                    )
                                    .aspectRatio(3 / 2, contentMode: .fit)
                                    .frame(width: geometry.size.width)
                                    .id(file.id)
                                }
                            }
                            .scrollTargetLayout()
                            .padding(.vertical, 12)
                        }
                        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
                        .scrollPosition(id: $scrollPositionID, anchor: .center)
                        .onChange(of: viewModel.selectedFileID, initial: true) { _, newID in
                            guard let newID,
                                  scrollPositionID != newID,
                                  files.contains(where: { $0.id == newID })
                            else { return }
                            withAnimation {
                                scrollPositionID = newID
                            }
                        }
                        .onChange(of: scrollPositionID) { _, newID in
                            guard let newID,
                                  viewModel.selectedFileID != newID,
                                  files.contains(where: { $0.id == newID })
                            else { return }
                            viewModel.selectedFileID = newID
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select Images to Compare",
                    systemImage: "rectangle.split.2x1",
                    description: Text("Select two to four thumbnails in a grid view, then use Compare."),
                )
            }
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigate(.left); return .handled }
        .onKeyPress(.rightArrow) { navigate(.right); return .handled }
        .onKeyPress(.escape) {
            if viewModel.activeBurstComparisonGroupID != nil {
                viewModel.returnToActiveBurstGroupView()
                return .handled
            }
            return .ignored
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJiIxXpP012345tTfFaAbB")) { press in
            switch press.characters {
            case "+": return increaseZoom()
            case "-": return decreaseZoom()
            case "j", "J": return toggleSelectedImageSource()
            case "i", "I": showCandidateInspector.toggle(); return .handled
            case "f", "F": return toggleSelectedFocusMask()
            case "a", "A": return toggleSelectedFocusPoints()
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
            finalistFocusActive = false
            selectFirstComparisonFileIfNeeded()
        }
        .onChange(of: viewModel.activeBurstComparisonGroupID) { _, _ in
            finalistFocusActive = false
            showCandidateInspector = false
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            Task {
                await regenerateFocusMasks()
            }
        }
    }

    private var files: [FileItem] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.filteredFiles.map { ($0.id, $0) })
        return comparisonDisplayFileIDs.compactMap { filesByID[$0] }
    }

    private var allComparisonFiles: [FileItem] {
        let filesByID = Dictionary(uniqueKeysWithValues: viewModel.filteredFiles.map { ($0.id, $0) })
        return viewModel.comparisonFileIDs.prefix(4).compactMap { filesByID[$0] }
    }

    private var comparisonDisplayFileIDs: [FileItem.ID] {
        if finalistFocusActive {
            let finalistIDs = ComparisonFinalistFocus.focusedIDs(from: burstComparisonResult)
            if !finalistIDs.isEmpty {
                return finalistIDs
            }
        }
        return Array(viewModel.comparisonFileIDs.prefix(4))
    }

    private var selectedComparisonFile: FileItem? {
        guard let selectedID = viewModel.selectedFileID else { return nil }
        return files.first { $0.id == selectedID }
    }

    private var burstComparisonResult: BurstAnalysisResult? {
        guard let groupID = viewModel.activeBurstComparisonGroupID else { return nil }
        return viewModel.burstAnalysisResult(for: groupID)
    }

    private var canApplyOneClickCulling: Bool {
        burstComparisonResult?.canApplyOneClickCulling(
            hasSharpnessScores: !viewModel.sharpnessModel.scores.isEmpty,
        ) ?? false
    }

    private var loadKey: String {
        files.map(\.id.uuidString).joined(separator: ",")
    }

    private func interactionBinding(for file: FileItem) -> Binding<ComparisonPaneInteractionState> {
        Binding(
            get: {
                interactionStates[file.id] ?? ComparisonPaneInteractionState()
            },
            set: { newValue in
                interactionStates[file.id] = newValue
            },
        )
    }

    private func loadImages() async {
        let currentFiles = files
        syncInteractionStates(for: currentFiles)
        imageStates = Dictionary(
            uniqueKeysWithValues: currentFiles.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: true))
            },
        )

        for file in currentFiles {
            guard !Task.isCancelled else { return }
            let useThumbnailSource = interactionStates[file.id]?.useThumbnailSource ?? false
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
            await populateFocusMask(in: &state, for: file)
            imageStates[file.id] = state
        }
    }

    private func syncInteractionStates(for currentFiles: [FileItem]) {
        let currentIDs = Set(currentFiles.map(\.id))
        interactionStates = interactionStates.filter { currentIDs.contains($0.key) }
        for file in currentFiles where interactionStates[file.id] == nil {
            interactionStates[file.id] = ComparisonPaneInteractionState()
        }
    }

    private func reloadImage(for file: FileItem) async {
        imageStates[file.id] = ComparisonImageState(id: file.id, isLoading: true)

        let useThumbnailSource = interactionStates[file.id]?.useThumbnailSource ?? false
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
        await populateFocusMask(in: &state, for: file)
        imageStates[file.id] = state
    }

    private func populateFocusMask(
        in state: inout ComparisonImageState,
        for file: FileItem,
    ) async {
        guard let cgImage = state.cgImage else { return }
        let downscaled = cgImage.downscaled(toWidth: 1024)
        let config = focusMaskConfig(for: file)
        let focusResult = await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: downscaled ?? cgImage,
            scale: 1.0,
            configOverride: config,
            afPoint: file.afFocusNormalized,
        )
        state.focusMask = focusResult.mask
        state.sharpnessBreakdown = focusResult.breakdown
        if let breakdown = focusResult.breakdown {
            viewModel.sharpnessModel.breakdowns[file.id] = breakdown
        }
        if let saliency = focusResult.saliency {
            viewModel.sharpnessModel.saliencyInfo[file.id] = saliency
        }
    }

    private func regenerateFocusMasks() async {
        for file in files {
            guard !Task.isCancelled else { return }
            guard let cgImage = imageStates[file.id]?.cgImage else { continue }
            let downscaled = cgImage.downscaled(toWidth: 1024)
            let config = focusMaskConfig(for: file)
            let result = await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
                from: downscaled ?? cgImage,
                scale: 1.0,
                configOverride: config,
                afPoint: file.afFocusNormalized,
            )
            guard !Task.isCancelled else { return }
            imageStates[file.id]?.focusMask = result.mask
            imageStates[file.id]?.sharpnessBreakdown = result.breakdown
            if let breakdown = result.breakdown {
                viewModel.sharpnessModel.breakdowns[file.id] = breakdown
            }
            if let saliency = result.saliency {
                viewModel.sharpnessModel.saliencyInfo[file.id] = saliency
            }
        }
    }

    private func focusMaskConfig(for file: FileItem) -> FocusDetectorConfig {
        var config = viewModel.sharpnessModel.effectiveFocusConfig
        config.iso = file.exifData?.isoValue ?? 400
        config.apertureHint = FocusDetectorConfig.ApertureHint.from(aperture: file.exifData?.apertureValue)
        if let score = viewModel.sharpnessModel.scores[file.id],
           SharpnessLabel(score: score, maxScore: viewModel.sharpnessModel.maxScore) == .sharp {
            config.guaranteeVisibleFocusEvidence = true
        }
        return config
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

    private func burstCandidate(
        for file: FileItem,
        in analysis: BurstAnalysisResult?,
    ) -> BurstCandidateScore? {
        guard let analysis,
              analysis.fileIDs.contains(file.id)
        else { return nil }
        return analysis.candidates.first { $0.fileID == file.id }
    }

    private func saliencyLabel(for file: FileItem) -> String? {
        viewModel.sharpnessModel.saliencyInfo[file.id]?.subjectLabel
    }

    private func sharpnessContext(for file: FileItem) -> SharpnessComparisonContext? {
        SharpnessComparisonSummary.context(
            for: file.id,
            fileIDs: files.map(\.id),
            scores: viewModel.sharpnessModel.scores,
            breakdowns: comparisonBreakdowns(),
            winnerID: comparisonWinnerFile()?.id,
        )
    }

    private func comparisonBreakdowns() -> [FileItem.ID: SharpnessBreakdown] {
        Dictionary(uniqueKeysWithValues: files.compactMap { file in
            guard let breakdown = imageStates[file.id]?.sharpnessBreakdown
                ?? viewModel.sharpnessModel.breakdowns[file.id]
            else { return nil }
            return (file.id, breakdown)
        })
    }

    private func comparisonWinnerFile() -> FileItem? {
        if let manual = viewModel.manualOverrideWinner(in: files)?.file {
            return manual
        }
        guard let winnerID = burstComparisonResult?.recommendedFileID else { return nil }
        return files.first { $0.id == winnerID }
    }

    private func selectFirstComparisonFileIfNeeded() {
        guard !files.isEmpty else { return }
        if let selectedID = viewModel.selectedFileID,
           files.contains(where: { $0.id == selectedID }) {
            return
        }
        viewModel.selectedFileID = files[0].id
    }

    private func inspectFinalists() {
        let finalistIDs = ComparisonFinalistFocus.focusedIDs(from: burstComparisonResult)
        guard !finalistIDs.isEmpty else { return }
        finalistFocusActive = true
        viewModel.selectedFileID = finalistIDs[0]
        showCandidateInspector = true
    }

    private func showAllCandidates() {
        finalistFocusActive = false
        selectFirstComparisonFileIfNeeded()
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let file = selectedComparisonFile else { return .ignored }
        viewModel.updateRating(for: file, rating: rating)
        return .handled
    }

    private func applyBurstKeepBest() -> KeyPress.Result {
        guard viewModel.activeBurstComparisonGroupID != nil,
              canApplyOneClickCulling,
              !allComparisonFiles.isEmpty
        else { return .ignored }
        viewModel.keepBestInGroup(from: allComparisonFiles)
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
        guard let action = ComparisonGridKeyAction.resolve(
            characters: event.characters,
            keyCode: event.keyCode,
        ) else { return .ignored }

        switch action {
        case let .navigate(direction):
            navigate(direction)
            return .handled

        case .escape:
            if viewModel.activeBurstComparisonGroupID != nil {
                viewModel.returnToActiveBurstGroupView()
                return .handled
            }
            return .ignored

        case .zoomIn:
            return increaseZoom()

        case .zoomOut:
            return decreaseZoom()

        case .toggleImageSource:
            return toggleSelectedImageSource()

        case .toggleFocusMask:
            return toggleSelectedFocusMask()

        case .toggleFocusPoints:
            return toggleSelectedFocusPoints()

        case .keepBest:
            return applyBurstKeepBest()

        case let .rating(rating):
            return applyRating(rating)
        }
    }

    private func navigate(_ direction: ComparisonGridNavigationDirection) {
        guard let selectedID = viewModel.selectedFileID,
              let currentIndex = files.firstIndex(where: { $0.id == selectedID }),
              let destinationIndex = ComparisonGridNavigation.destinationIndex(
                  from: currentIndex,
                  itemCount: files.count,
                  direction: direction,
              )
        else { return }

        viewModel.selectedFileID = files[destinationIndex].id
    }

    @discardableResult
    private func updateSelectedInteraction(
        _ update: (inout ComparisonPaneInteractionState) -> Void,
    ) -> KeyPress.Result {
        guard let selectedID = viewModel.selectedFileID,
              files.contains(where: { $0.id == selectedID })
        else { return .ignored }

        var state = interactionStates[selectedID] ?? ComparisonPaneInteractionState()
        update(&state)
        interactionStates[selectedID] = state
        return .handled
    }

    private func toggleSelectedFocusMask() -> KeyPress.Result {
        updateSelectedInteraction { $0.showFocusMask.toggle() }
    }

    private func toggleSelectedFocusPoints() -> KeyPress.Result {
        updateSelectedInteraction { $0.showFocusPoints.toggle() }
    }

    private func toggleSelectedImageSource() -> KeyPress.Result {
        updateSelectedInteraction { $0.useThumbnailSource.toggle() }
    }

    private func increaseZoom() -> KeyPress.Result {
        updateSelectedInteraction { state in
            withAnimation(.spring()) {
                state.scale = min(5.0, state.scale + 0.4)
                state.lastScale = state.scale
            }
        }
    }

    private func decreaseZoom() -> KeyPress.Result {
        updateSelectedInteraction { state in
            withAnimation(.spring()) {
                state.scale = max(0.5, state.scale - 0.4)
                state.lastScale = state.scale
            }
        }
    }
}

private struct BurstComparisonEvidenceView: View {
    let result: BurstAnalysisResult
    let selectedFile: FileItem?
    let canApplyOneClickCulling: Bool
    let onKeepBest: () -> Void
    let onKeepTopTwo: () -> Void
    let finalistFocusActive: Bool
    let onInspectFinalists: () -> Void
    let onShowAll: () -> Void
    let onSetManualWinner: (FileItem) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Burst \(result.groupID + 1) Comparison")
                    .font(.headline)
                Text(result.confidence.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if result.reviewState == .manualWinnerOverride {
                    Text("Manual winner active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if finalistFocusActive {
                    Button("Show All", action: onShowAll)
                        .controlSize(.small)
                }
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
                    Button("Inspect Finalists", action: onInspectFinalists)
                        .disabled(result.candidates.isEmpty)
                    Button("Set Manual Winner") {
                        if let selectedFile {
                            onSetManualWinner(selectedFile)
                        }
                    }
                    .disabled(!selectedFileIsInResult)
                    .help(selectedFileIsInResult ? "Save the selected frame as the manual burst winner" : "Select a frame in this burst")
                    if canApplyOneClickCulling {
                        Button("Keep Best", action: onKeepBest)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                        Button("Keep Top 2", action: onKeepTopTwo)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var selectedFileIsInResult: Bool {
        guard let selectedFile else { return false }
        return result.fileIDs.contains(selectedFile.id)
    }
}
