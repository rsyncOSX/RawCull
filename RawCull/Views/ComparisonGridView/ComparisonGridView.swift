import AppKit
import RawCullCore
import SwiftUI

struct ComparisonGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var showCandidateInspector: Bool

    @State private var imageStates: [FileItem.ID: ComparisonImageState] = [:]
    @State private var viewportState = ComparisonViewportInteractionState()
    @State private var useThumbnailSourceByFileID: [FileItem.ID: Bool] = [:]
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
                        .padding(.horizontal, 4)
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
                                        viewportState: $viewportState,
                                        useThumbnailSource: useThumbnailSourceBinding(for: file),
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
                            .padding(.vertical, 4)
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

    private func useThumbnailSourceBinding(for file: FileItem) -> Binding<Bool> {
        Binding(
            get: {
                useThumbnailSourceByFileID[file.id] ?? false
            },
            set: { newValue in
                useThumbnailSourceByFileID[file.id] = newValue
            },
        )
    }

    private func loadImages() async {
        let currentFiles = files
        syncSourceStates(for: currentFiles)
        imageStates = Dictionary(
            uniqueKeysWithValues: currentFiles.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: true))
            },
        )

        for file in currentFiles {
            guard !Task.isCancelled else { return }
            let useThumbnailSource = useThumbnailSourceByFileID[file.id] ?? false
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

    private func syncSourceStates(for currentFiles: [FileItem]) {
        let currentIDs = Set(currentFiles.map(\.id))
        useThumbnailSourceByFileID = useThumbnailSourceByFileID.filter { currentIDs.contains($0.key) }
        for file in currentFiles where useThumbnailSourceByFileID[file.id] == nil {
            useThumbnailSourceByFileID[file.id] = false
        }
    }

    private func reloadImage(for file: FileItem) async {
        imageStates[file.id] = ComparisonImageState(id: file.id, isLoading: true)

        let useThumbnailSource = useThumbnailSourceByFileID[file.id] ?? false
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
    private func selectedFileIDForInteraction() -> FileItem.ID? {
        guard let selectedID = viewModel.selectedFileID,
              files.contains(where: { $0.id == selectedID })
        else { return nil }

        return selectedID
    }

    private func toggleSelectedFocusMask() -> KeyPress.Result {
        guard selectedFileIDForInteraction() != nil else { return .ignored }
        viewportState.showFocusMask.toggle()
        return .handled
    }

    private func toggleSelectedFocusPoints() -> KeyPress.Result {
        guard selectedFileIDForInteraction() != nil else { return .ignored }
        viewportState.showFocusPoints.toggle()
        return .handled
    }

    private func toggleSelectedImageSource() -> KeyPress.Result {
        guard let selectedID = selectedFileIDForInteraction() else { return .ignored }
        useThumbnailSourceByFileID[selectedID, default: false].toggle()
        return .handled
    }

    private func increaseZoom() -> KeyPress.Result {
        guard selectedFileIDForInteraction() != nil else { return .ignored }
        withAnimation(.spring()) {
            viewportState.scale = min(5.0, viewportState.scale + 0.4)
            viewportState.lastScale = viewportState.scale
        }
        return .handled
    }

    private func decreaseZoom() -> KeyPress.Result {
        guard selectedFileIDForInteraction() != nil else { return .ignored }
        withAnimation(.spring()) {
            viewportState.scale = max(0.5, viewportState.scale - 0.4)
            viewportState.lastScale = viewportState.scale
        }
        return .handled
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
        HStack(spacing: 8) {
            Text("Burst \(result.groupID + 1)")
                .font(.subheadline.weight(.semibold))

            Text(result.confidence.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if result.reviewState == .manualWinnerOverride {
                Text("Manual winner")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if let firstReason = result.reasons.first {
                Text("Evidence: \(firstReason)")
                    .foregroundStyle(.secondary)
                    .help(evidenceHelp)
            }

            if let firstCaution = result.cautions.first {
                Text("Caution: \(firstCaution)")
                    .foregroundStyle(.orange)
                    .help(cautionHelp)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if finalistFocusActive {
                    Button("Show All", action: onShowAll)
                }
                Button("Back To Group", action: onBack)
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
            .controlSize(.mini)
        }
        .font(.caption)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var evidenceHelp: String {
        result.reasons.joined(separator: "\n")
    }

    private var cautionHelp: String {
        result.cautions.joined(separator: "\n")
    }

    private var selectedFileIsInResult: Bool {
        guard let selectedFile else { return false }
        return result.fileIDs.contains(selectedFile.id)
    }
}
