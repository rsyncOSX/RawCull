//
//  ZoomOverlayView.swift
//  RawCull
//
//  Full-window zoom overlay. Replaces the older separate zoom windows by
//  covering the main window in a ZStack above the normal content. Dismiss
//  via Escape, the close button, or a second double-tap.
//

import AppKit
import SwiftUI

nonisolated enum ZoomOverlayKeyAction: Equatable {
    case navigatePrevious
    case navigateNext
    case escape
    case zoomIn
    case zoomOut
    case toggleThumbnailSource
    case toggleFocusMask
    case toggleFocusPoints
    case rating(Int)

    nonisolated static func resolve(
        characters: String?,
        keyCode: UInt16,
        navigationAxis: ZoomOverlayNavigationAxis,
    ) -> ZoomOverlayKeyAction? {
        if let action = action(for: characters) {
            return action
        }

        return switch (navigationAxis, keyCode) {
        case (.horizontal, 123), (.vertical, 126):
            .navigatePrevious

        case (.horizontal, 124), (.vertical, 125):
            .navigateNext

        case (_, 53):
            .escape

        default:
            nil
        }
    }

    private nonisolated static func action(for characters: String?) -> ZoomOverlayKeyAction? {
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "j", "J":
            .toggleThumbnailSource

        case "f", "F":
            .toggleFocusMask

        case "a", "A":
            .toggleFocusPoints

        case "x", "X":
            .rating(-1)

        case "p", "P", "0":
            .rating(0)

        case "1", "2":
            .rating(2)

        case "3", "t", "T":
            .rating(3)

        case "4":
            .rating(4)

        case "5":
            .rating(5)

        default:
            nil
        }
    }
}

nonisolated struct ZoomOverlayNavigationContext: Equatable, Sendable {
    let orderedFileIDs: [FileItem.ID]

    init(orderedFileIDs: [FileItem.ID]) {
        var seen = Set<FileItem.ID>()
        self.orderedFileIDs = orderedFileIDs.filter { seen.insert($0).inserted }
    }

    func destinationID(from currentID: FileItem.ID, delta: Int) -> FileItem.ID? {
        guard let currentIndex = orderedFileIDs.firstIndex(of: currentID) else { return nil }
        let destinationIndex = currentIndex + delta
        guard orderedFileIDs.indices.contains(destinationIndex) else { return nil }
        return orderedFileIDs[destinationIndex]
    }

    func canNavigatePrevious(from currentID: FileItem.ID) -> Bool {
        destinationID(from: currentID, delta: -1) != nil
    }

    func canNavigateNext(from currentID: FileItem.ID) -> Bool {
        destinationID(from: currentID, delta: 1) != nil
    }
}

struct ZoomOverlayView: View {
    @Bindable var viewModel: RawCullViewModel

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    @State private var focusMask: CGImage?
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFocusMask: Bool = false
    @State private var showFocusPoints: Bool = false
    @State private var useThumbnailSource: Bool = true
    @State private var focusBreakdown: SharpnessBreakdown?
    @State private var sharpnessInspectorExpanded = true
    @State private var maskTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @FocusState private var isImageFocused: Bool

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.97).ignoresSafeArea()

            GeometryReader { geo in
                ZStack {
                    if let cg = viewModel.zoomOverlayCGImage {
                        zoomableCGImage(cg, in: geo.size)
                    } else if let ns = viewModel.zoomOverlayNSImage {
                        zoomableNSImage(ns, in: geo.size)
                    } else {
                        HStack {
                            ProgressView().fixedSize()
                            Text("Extracting image…").font(.title)
                        }
                        .padding()
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    focusPoint()
                }
            }

            VStack {
                HStack {
                    if let selectedFile = viewModel.selectedFile {
                        HStack(spacing: 6) {
                            CurrentRatingBadgeView(rating: ratingDisplay(for: selectedFile))
                            zoomAnalysisBadges(for: selectedFile)
                        }
                        .padding()
                    }

                    Spacer()

                    navigationButton(
                        previousNavigationIcon,
                        help: previousNavigationHelp,
                        isDisabled: !canNavigatePrevious,
                    ) {
                        navigateSelection(by: -1)
                    }

                    navigationButton(
                        nextNavigationIcon,
                        help: nextNavigationHelp,
                        isDisabled: !canNavigateNext,
                    ) {
                        navigateSelection(by: 1)
                    }

                    toolbarButton("xmark.circle") { dismiss() }
                }

                Spacer()

                VStack(spacing: 8) {
                    if let selectedFile = viewModel.selectedFile {
                        RatingActionBarView(
                            currentRating: ratingDisplay(for: selectedFile),
                            onSelect: { rating in
                                viewModel.updateRating(for: selectedFile, rating: rating)
                            },
                        )
                    }

                    if showFocusMask, let selectedFile = viewModel.selectedFile {
                        SharpnessBreakdownInspectorView(
                            fileName: selectedFile.name,
                            score: viewModel.sharpnessModel.scores[selectedFile.id],
                            maxScore: viewModel.sharpnessModel.maxScore,
                            breakdown: focusBreakdown ?? viewModel.sharpnessModel.breakdowns[selectedFile.id],
                            isExpanded: $sharpnessInspectorExpanded,
                        )
                        .frame(maxWidth: 360)
                    }

                    Text(currentScale <= 1.0 ? "Double-click to zoom" : "Double-click to fit")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))

                    if let cg = viewModel.zoomOverlayCGImage {
                        Text("\(cg.width) × \(cg.height) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    } else if let ns = viewModel.zoomOverlayNSImage {
                        Text("\(Int(ns.size.width)) × \(Int(ns.size.height)) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    ImageOverlayControlsView(
                        showFocusMask: $showFocusMask,
                        focusMaskAvailable: focusMask != nil,
                        hasFocusPoints: focusPoints != nil,
                        showFocusPoints: $showFocusPoints,
                        showShortcutHints: true,
                        showImageSourceToggle: true,
                        useThumbnailSource: $useThumbnailSource,
                        scale: currentScale,
                        canZoomOut: currentScale > 0.5,
                        canZoomIn: currentScale < 5.0,
                        canReset: currentScale != 1.0 || offset != .zero,
                        onZoomOut: { decreaseZoom() },
                        onZoomReset: { withAnimation(.spring()) { resetToFit() } },
                        onZoomIn: { increaseZoom() },
                    )
                }
                .padding(.bottom, 20)
            }

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .focusable()
        .focused($isImageFocused)
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 123,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.rightArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 124,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.upArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 126,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.downArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 125,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJfFaAxXpP012345tT")) { press in
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: press.characters,
                keyCode: 0,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onAppear {
            isImageFocused = true
            installKeyMonitor()
            reload()
        }
        .onDisappear {
            removeKeyMonitor()
            maskTask?.cancel()
            maskTask = nil
            focusMask = nil
        }
        .onChange(of: useThumbnailSource) { _, _ in reload() }
        .onChange(of: viewModel.selectedFile) { _, _ in
            guard viewModel.zoomOverlayVisible else { return }
            reload()
        }
        .task(id: viewModel.zoomOverlayCGImage?.hashValue) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await regenerateMaskFromCG()
        }
        .onChange(of: viewModel.sharpnessModel.focusMaskModel.config) { _, _ in
            maskTask?.cancel()
            maskTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await regenerateMaskFromCG()
            }
        }
    }

    // MARK: - Reload

    private func reload() {
        guard let file = viewModel.selectedFile else { return }
        viewModel.zoomExtractionTask?.cancel()
        focusBreakdown = nil
        viewModel.zoomExtractionTask = ZoomPreviewHandler.handleOverlay(
            file: file,
            useThumbnailAsZoomPreview: useThumbnailSource,
            viewModel: viewModel,
        )
    }

    private var orderedZoomFiles: [FileItem] {
        if let context = viewModel.zoomOverlayNavigationContext {
            let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
            let contextualFiles = context.orderedFileIDs.compactMap { filesByID[$0] }
            if !contextualFiles.isEmpty {
                return contextualFiles
            }
        }

        let filtered = viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
        return viewModel.sharpnessModel.sortBySharpness
            ? filtered
            : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var currentZoomIndex: Int? {
        guard let selectedFile = viewModel.selectedFile else { return nil }
        return orderedZoomFiles.firstIndex { $0.id == selectedFile.id }
    }

    private var usesVerticalNavigation: Bool {
        viewModel.zoomOverlayNavigationAxis == .vertical
    }

    private var previousNavigationIcon: String {
        usesVerticalNavigation ? "chevron.up.circle" : "chevron.left.circle"
    }

    private var nextNavigationIcon: String {
        usesVerticalNavigation ? "chevron.down.circle" : "chevron.right.circle"
    }

    private var previousNavigationHelp: String {
        usesVerticalNavigation ? "Previous image (Up)" : "Previous image"
    }

    private var nextNavigationHelp: String {
        usesVerticalNavigation ? "Next image (Down)" : "Next image"
    }

    private var canNavigatePrevious: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex > 0
    }

    private var canNavigateNext: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex + 1 < orderedZoomFiles.count
    }

    private func navigateSelection(by delta: Int) {
        guard let currentZoomIndex else { return }
        let newIndex = currentZoomIndex + delta
        guard orderedZoomFiles.indices.contains(newIndex) else { return }
        recenterForNavigatedImage()
        viewModel.selectedFileID = orderedZoomFiles[newIndex].id
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.zoomOverlayVisible,
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
        handleKeyAction(ZoomOverlayKeyAction.resolve(
            characters: event.characters,
            keyCode: event.keyCode,
            navigationAxis: viewModel.zoomOverlayNavigationAxis,
        ))
    }

    private func handleKeyAction(_ action: ZoomOverlayKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }

        switch action {
        case .navigatePrevious:
            navigateSelection(by: -1)
            return .handled

        case .navigateNext:
            navigateSelection(by: 1)
            return .handled

        case .escape:
            dismiss()
            return .handled

        case .zoomIn:
            increaseZoom()
            return .handled

        case .zoomOut:
            decreaseZoom()
            return .handled

        case .toggleThumbnailSource:
            useThumbnailSource.toggle()
            return .handled

        case .toggleFocusMask:
            showFocusMask.toggle()
            return .handled

        case .toggleFocusPoints:
            showFocusPoints.toggle()
            return .handled

        case let .rating(rating):
            return applyRating(rating)
        }
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard let selectedFile = viewModel.selectedFile else { return .ignored }
        viewModel.updateRating(for: selectedFile, rating: rating)
        return .handled
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    @ViewBuilder
    private func zoomAnalysisBadges(for file: FileItem) -> some View {
        let settings = SettingsViewModel.shared
        let score = viewModel.sharpnessModel.scores[file.id]

        if settings.showScoringBadge, let score {
            SharpnessBadgeView(
                score: score,
                maxScore: viewModel.sharpnessModel.maxScore,
            )
        }

        if settings.showSaliencyBadge {
            if let saliency = viewModel.sharpnessModel.saliencyInfo[file.id] {
                SaliencyBadgeView(info: saliency)
            } else if score != nil {
                NoSubjectBadgeView()
            }
        }
    }

    // MARK: - Dismiss

    private func dismiss() {
        viewModel.closeZoomOverlay()
        resetToFit()
        focusMask = nil
        focusBreakdown = nil
    }

    // MARK: - Mask regeneration

    private func regenerateMaskFromCG() async {
        guard let cg = viewModel.zoomOverlayCGImage,
              let selectedFile = viewModel.selectedFile
        else { return }
        let downscaled = cg.downscaled(toWidth: 1024)
        let result = await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: downscaled ?? cg,
            scale: 1.0,
            afPoint: selectedFile.afFocusNormalized,
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.focusMask = result.mask
            self.focusBreakdown = result.breakdown
            if let breakdown = result.breakdown {
                viewModel.sharpnessModel.breakdowns[selectedFile.id] = breakdown
            }
            if let saliency = result.saliency {
                viewModel.sharpnessModel.saliencyInfo[selectedFile.id] = saliency
            }
        }
    }

    // MARK: - Zoomable images

    private func zoomableCGImage(_ image: CGImage, in size: CGSize) -> some View {
        ZStack {
            Image(decorative: image, scale: 1.0, orientation: .up)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)

            if showFocusMask, let mask = focusMask {
                Image(decorative: mask, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)
                    .blendMode(.screen)
                    .opacity(0.95)
                    .transition(.opacity)
            }
        }
        .scaleEffect(currentScale)
        .offset(offset)
        .gesture(zoomPanGesture)
        .onTapGesture(count: 2) {
            withAnimation(.spring()) { currentScale > 1.0 ? resetToFit() : zoomToTarget() }
        }
    }

    private func zoomableNSImage(_ image: NSImage, in size: CGSize) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)
        }
        .scaleEffect(currentScale)
        .offset(offset)
        .gesture(zoomPanGesture)
        .onTapGesture(count: 2) {
            withAnimation(.spring()) { currentScale > 1.0 ? resetToFit() : zoomToTarget() }
        }
    }

    private var zoomPanGesture: some Gesture {
        SimultaneousGesture(
            MagnificationGesture()
                .onChanged { currentScale = lastScale * $0 }
                .onEnded { _ in
                    lastScale = currentScale
                    if currentScale < 1.0 { withAnimation(.spring()) { resetToFit() } }
                },
            DragGesture()
                .onChanged { value in
                    if currentScale > 1.0 {
                        offset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height,
                        )
                    }
                }
                .onEnded { _ in lastOffset = offset },
        )
    }

    // MARK: - Focus point overlay

    @ViewBuilder
    private func focusPoint() -> some View {
        if showFocusPoints, let focusPoints {
            let imageSize: CGSize? = {
                if let cg = viewModel.zoomOverlayCGImage {
                    return CGSize(width: cg.width, height: cg.height)
                } else if let ns = viewModel.zoomOverlayNSImage {
                    return ns.size
                }
                return nil
            }()
            FocusOverlayView(
                focusPoints: focusPoints,
                imageSize: imageSize,
                markerSize: viewModel.focusPointMarkerSize,
            )
            .scaleEffect(currentScale)
            .offset(offset)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }

    // MARK: - Toolbar button

    private func toolbarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Material.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
        .padding()
    }

    private func navigationButton(
        _ icon: String,
        help: String,
        isDisabled: Bool,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(isDisabled ? .white.opacity(0.35) : .white)
                .frame(width: 30, height: 30)
                .background(Material.regularMaterial)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .shadow(color: .black.opacity(isDisabled ? 0 : 0.4), radius: 8, x: 0, y: 2)
        .padding(.vertical)
        .padding(.trailing, 2)
    }

    // MARK: - Zoom helpers

    private func resetToFit() {
        currentScale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
    }

    private func recenterForNavigatedImage() {
        offset = .zero
        lastOffset = .zero
    }

    private func zoomToTarget() {
        currentScale = zoomLevel; lastScale = zoomLevel; offset = .zero; lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) { currentScale = min(5.0, currentScale + 0.4) }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) { currentScale = max(0.5, currentScale - 0.4) }
    }
}

private struct SharpnessBreakdownInspectorView: View {
    let fileName: String
    let score: Float?
    let maxScore: Float
    let breakdown: SharpnessBreakdown?
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 7) {
                if let breakdown {
                    row("Global", value: percent(breakdown.globalScore))
                    row("Subject", value: percent(breakdown.subjectScore))
                    row("AF point", value: percent(breakdown.afPointScore))
                    row("Blur gate", value: sigma(breakdown.blurGateSigma))
                    if let subject = breakdown.subjectLabel {
                        row("Subject label", value: subject)
                    }
                    row("Saliency", value: percent(breakdown.subjectConfidence))
                    row("Focus flag", value: breakdown.focusFailureKind.title)
                } else if let score {
                    row("Sharpness", value: percent(score / Swift.max(maxScore, 1e-6)))
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "viewfinder")
                Text("Sharpness")
                    .font(.caption.weight(.semibold))
                Text(fileName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }

    private func row(_ title: String, value: String?) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.system(.caption, design: .monospaced))
        }
    }

    private func percent(_ value: Float?) -> String? {
        guard let value, value.isFinite else { return nil }
        return "\(Int((value * 100).rounded()))"
    }

    private func sigma(_ value: Float) -> String {
        String(format: "%.3f", value)
    }
}

extension CGImage {
    func downscaled(toWidth maxWidth: Int) -> CGImage? {
        guard width > maxWidth else { return self }
        let scale = CGFloat(maxWidth) / CGFloat(width)
        let newWidth = maxWidth
        let newHeight = Int(CGFloat(height) * scale)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
