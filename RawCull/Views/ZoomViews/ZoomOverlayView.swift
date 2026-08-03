//
//  ZoomOverlayView.swift
//  RawCull
//
//  Full-window zoom overlay. Replaces the older separate zoom windows by
//  covering the main window in a ZStack above the normal content. Dismiss
//  via Escape, the close button, or a second double-tap.
//

import AppKit
import RawCullCore
import SwiftUI

nonisolated enum ZoomOverlayKeyAction: Equatable {
    case navigatePrevious
    case navigateNext
    case escape
    case zoomIn
    case zoomOut
    case toggleEmbeddedJPG
    case toggleDevelopedRAW
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
            .toggleEmbeddedJPG

        case "r", "R":
            .toggleDevelopedRAW

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

nonisolated struct ZoomOverlayNavigationContext: Equatable {
    let orderedFileIDs: [FileItem.ID]

    init(orderedFileIDs: [FileItem.ID]) {
        var seen = Set<FileItem.ID>()
        self.orderedFileIDs = orderedFileIDs.filter { seen.insert($0).inserted }
    }

    // periphery:ignore
    func destinationID(from currentID: FileItem.ID, delta: Int) -> FileItem.ID? {
        guard let currentIndex = orderedFileIDs.firstIndex(of: currentID) else { return nil }
        let destinationIndex = currentIndex + delta
        guard orderedFileIDs.indices.contains(destinationIndex) else { return nil }
        return orderedFileIDs[destinationIndex]
    }

    // periphery:ignore
    func canNavigatePrevious(from currentID: FileItem.ID) -> Bool {
        destinationID(from: currentID, delta: -1) != nil
    }

    // periphery:ignore
    func canNavigateNext(from currentID: FileItem.ID) -> Bool {
        destinationID(from: currentID, delta: 1) != nil
    }
}

nonisolated struct ZoomViewportTransform: Equatable {
    var scale: CGFloat
    var offset: CGSize
}

nonisolated enum ZoomViewportMath {
    static func aspectFitRect(imageSize: CGSize, in viewportSize: CGSize) -> CGRect {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              viewportSize.width.isFinite, viewportSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0
        else { return .zero }

        let scale = min(viewportSize.width / imageSize.width, viewportSize.height / imageSize.height)
        guard scale.isFinite, scale > 0 else { return .zero }
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        guard size.width.isFinite, size.height.isFinite else { return .zero }
        return CGRect(
            x: (viewportSize.width - size.width) / 2,
            y: (viewportSize.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }

    static func actualPixelsScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        let fitRect = aspectFitRect(imageSize: imageSize, in: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else { return 1.0 }
        let fitScale = min(fitRect.width / imageSize.width, fitRect.height / imageSize.height)
        guard fitScale > 0, fitScale.isFinite else { return 1.0 }
        return 1.0 / fitScale
    }

    static func actualPixelsTransform(
        imageSize: CGSize,
        viewportSize: CGSize,
        normalizedFocusPoint: CGPoint?,
    ) -> ZoomViewportTransform {
        let scale = actualPixelsScale(imageSize: imageSize, viewportSize: viewportSize)
        guard let normalizedFocusPoint,
              normalizedFocusPoint.x.isFinite,
              normalizedFocusPoint.y.isFinite
        else {
            return ZoomViewportTransform(scale: scale, offset: .zero)
        }

        let fitRect = aspectFitRect(imageSize: imageSize, in: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else {
            return ZoomViewportTransform(scale: scale, offset: .zero)
        }

        let point = CGPoint(
            x: fitRect.minX + normalizedFocusPoint.x * fitRect.width,
            y: fitRect.minY + normalizedFocusPoint.y * fitRect.height,
        )
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let desiredOffset = CGSize(
            width: (viewportCenter.x - point.x) * scale,
            height: (viewportCenter.y - point.y) * scale,
        )
        let scaledImageSize = CGSize(width: fitRect.width * scale, height: fitRect.height * scale)
        return ZoomViewportTransform(
            scale: scale,
            offset: clampedOffset(desiredOffset, scaledImageSize: scaledImageSize, viewportSize: viewportSize),
        )
    }

    private static func clampedOffset(
        _ offset: CGSize,
        scaledImageSize: CGSize,
        viewportSize: CGSize,
    ) -> CGSize {
        let maxX = max(0, (scaledImageSize.width - viewportSize.width) / 2)
        let maxY = max(0, (scaledImageSize.height - viewportSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY),
        )
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
    @State private var sourceSelection = ImageSourceSelectionState()
    @State private var showRAWNotSupported = false
    @State private var rawMessageTask: Task<Void, Never>?
    @State private var maskTask: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @State private var pendingInitialZoomMode: ZoomOverlayInitialZoomMode?
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

                    if showRAWNotSupported {
                        Text("Not supported")
                            .font(.title2.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(.regularMaterial, in: Capsule())
                            .transition(.opacity)
                    }
                }
            }

            VStack {
                HStack {
                    if let selectedFile = viewModel.selectedFile {
                        HStack(spacing: 6) {
                            CurrentRatingBadgeView(rating: ratingDisplay(for: selectedFile))
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
                                viewModel.updateRatingAndAdvance(for: selectedFile, rating: rating, in: orderedZoomFiles)
                            },
                        )
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
                        hasFocusPoints: focusTarget != nil,
                        showFocusPoints: $showFocusPoints,
                        showShortcutHints: true,
                        showImageSourceToggle: true,
                        useThumbnailSource: useThumbnailSourceBinding,
                        imageSourceSelection: $sourceSelection,
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
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFaAxXpP012345tT")) { press in
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: press.characters,
                keyCode: 0,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onAppear {
            isImageFocused = true
            installKeyMonitor()
            applyLaunchContext()
            reload()
        }
        .onDisappear {
            removeKeyMonitor()
            maskTask?.cancel()
            maskTask = nil
            focusMask = nil
            rawMessageTask?.cancel()
            rawMessageTask = nil
        }
        .onChange(of: sourceSelection.selected) { _, _ in reload() }
        .onChange(of: viewModel.selectedFile) { _, _ in
            guard viewModel.zoomOverlayVisible else { return }
            sourceSelection.resetForNewImage()
            clearRAWMessage()
            pendingInitialZoomMode = viewModel.zoomOverlayLaunchContext.initialZoomMode
            reload()
        }
        .task(id: viewModel.zoomOverlayCGImage?.hashValue) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await regenerateMaskFromCG()
        }
        .onChange(of: viewModel.sharpnessModel.effectiveFocusConfig) { _, _ in
            maskTask?.cancel()
            maskTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await regenerateMaskFromCG()
            }
        }
    }

    // MARK: - Reload

    private func applyLaunchContext() {
        let context = viewModel.zoomOverlayLaunchContext
        sourceSelection.select(context.initialSource)
        pendingInitialZoomMode = context.initialZoomMode
        if context.showFocusPointsOnOpen {
            showFocusPoints = focusTarget != nil
        }
    }

    private func reload() {
        guard let file = viewModel.selectedFile else { return }
        viewModel.zoomExtractionTask?.cancel()
        viewModel.zoomExtractionTask = ZoomPreviewHandler.handleOverlay(
            file: file,
            source: sourceSelection.selected,
            viewModel: viewModel,
            onDevelopedRAWFailure: {
                sourceSelection.markDevelopedRAWUnavailable()
                showRAWFailureMessage()
            },
        )
    }

    private var useThumbnailSourceBinding: Binding<Bool> {
        Binding(
            get: { sourceSelection.selected == .thumbnail },
            set: { sourceSelection.select($0 ? .thumbnail : .embeddedJPG) },
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
        prepareForNavigatedImage()
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

        case .toggleEmbeddedJPG:
            sourceSelection.toggleExtractionSource(.embeddedJPG)
            return .handled

        case .toggleDevelopedRAW:
            sourceSelection.toggleExtractionSource(.developedRAW)
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
        viewModel.updateRatingAndAdvance(for: selectedFile, rating: rating, in: orderedZoomFiles)
        return .handled
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    // MARK: - Dismiss

    private func dismiss() {
        viewModel.closeZoomOverlay()
        resetToFit()
        focusMask = nil
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

    // MARK: - Mask regeneration

    private func regenerateMaskFromCG() async {
        guard let cg = viewModel.zoomOverlayCGImage,
              let selectedFile = viewModel.selectedFile
        else { return }
        let downscaled = cg.downscaled(toWidth: 1024)
        let source = downscaled ?? cg
        let config = focusMaskConfig(for: selectedFile)
        let result = await viewModel.sharpnessModel.focusMaskModel.generateFocusMaskWithBreakdown(
            from: source,
            scale: 1.0,
            configOverride: config,
            afPoint: selectedFile.afFocusNormalized,
            iso: selectedFile.exifData?.isoValue ?? 400,
            aperture: selectedFile.exifData?.apertureValue,
            scoringSource: sourceSelection.selected == .developedRAW ? .rawDemosaic : .embeddedPreview,
        )
        guard !Task.isCancelled else { return }
        await MainActor.run {
            self.focusMask = result.mask
            if let breakdown = result.breakdown {
                viewModel.sharpnessModel.breakdowns[selectedFile.id] = breakdown
            }
            if let saliency = result.saliency {
                viewModel.sharpnessModel.saliencyInfo[selectedFile.id] = saliency
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
        .onAppear {
            applyPendingInitialZoomIfNeeded(imageSize: CGSize(width: image.width, height: image.height), viewportSize: size)
        }
        .onChange(of: viewModel.zoomOverlayCGImage?.hashValue) { _, _ in
            applyPendingInitialZoomIfNeeded(imageSize: CGSize(width: image.width, height: image.height), viewportSize: size)
        }
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
                    if currentScale < 1.0 {
                        withAnimation(.spring()) { resetToFit() }
                    }
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

    private var focusTarget: CGPoint? {
        if let point = focusPoints?.first {
            return CGPoint(x: point.normalizedX, y: point.normalizedY)
        }
        return viewModel.selectedFile?.afFocusNormalized
    }

    @ViewBuilder
    private func focusPoint() -> some View {
        if showFocusPoints, let focusTarget {
            let imageSize: CGSize? = {
                if let cg = viewModel.zoomOverlayCGImage {
                    return CGSize(width: cg.width, height: cg.height)
                } else if let ns = viewModel.zoomOverlayNSImage {
                    return ns.size
                }
                return nil
            }()
            FocusPointMarker(
                normalizedX: focusTarget.x,
                normalizedY: focusTarget.y,
                boxSize: 16,
                imageSize: imageSize,
            )
            .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
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

    private func prepareForNavigatedImage() {
        offset = .zero
        lastOffset = .zero
        pendingInitialZoomMode = viewModel.zoomOverlayLaunchContext.initialZoomMode
    }

    private func zoomToTarget() {
        currentScale = zoomLevel; lastScale = zoomLevel; offset = .zero; lastOffset = .zero
    }

    private func applyPendingInitialZoomIfNeeded(imageSize: CGSize, viewportSize: CGSize) {
        guard pendingInitialZoomMode == .actualPixels else { return }
        let transform = ZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: focusTarget,
        )
        currentScale = transform.scale
        lastScale = transform.scale
        offset = transform.offset
        lastOffset = transform.offset
        pendingInitialZoomMode = nil
    }

    private func increaseZoom() {
        withAnimation(.spring()) { currentScale = min(5.0, currentScale + 0.4) }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) { currentScale = max(0.5, currentScale - 0.4) }
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
