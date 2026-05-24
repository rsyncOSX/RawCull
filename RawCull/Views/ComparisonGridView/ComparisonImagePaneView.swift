import SwiftUI

struct ComparisonImagePaneView: View {
    let file: FileItem
    let state: ComparisonImageState?
    let focusPoints: [FocusPoint]?
    @Binding var interactionState: ComparisonPaneInteractionState
    let markerSize: CGFloat
    let isSelected: Bool
    let rating: RatingDisplay
    let exifSummary: ExifSummary
    let saliencyLabel: String?
    let burstAnalysis: BurstAnalysisResult?
    let burstCandidate: BurstCandidateScore?
    let burstRating: Int
    let sharpnessContext: SharpnessComparisonContext?
    let inspectorIsPresented: Bool
    let onSelect: () -> Void
    let onRate: (Int) -> Void
    let onToggleInspector: () -> Void
    let onSourceChange: () -> Void

    @State private var isHovered = false

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                if let state {
                    imageContent(state, in: geo.size)
                } else {
                    ProgressView()
                        .fixedSize()
                }

                if showsPaneChrome {
                    paneChrome
                        .transition(.opacity)
                }
            }
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(Rectangle())
            .gesture(zoomPanGesture)
            .onTapGesture(count: 1, perform: onSelect)
            .onTapGesture(count: 2) {
                onSelect()
                toggleZoom()
            }
            .onHover { isHovered = $0 }
            .onChange(of: interactionState.useThumbnailSource) { _, _ in
                onSourceChange()
            }
            .animation(.easeInOut(duration: 0.16), value: showsPaneChrome)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0),
        )
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.55) : .clear,
            radius: isSelected ? 10 : 0,
        )
        .clipShape(.rect(cornerRadius: 8))
    }

    private var showsPaneChrome: Bool {
        isSelected || isHovered
    }

    private var focusMaskAvailable: Bool {
        state?.focusMask != nil
    }

    private var hasFocusPoints: Bool {
        focusPoints != nil
    }

    private var paneChrome: some View {
        VStack(spacing: 8) {
            headerOverlay
            Spacer()
            VStack(spacing: 8) {
                RatingActionBarView(
                    currentRating: rating,
                    onSelect: { rating in
                        onSelect()
                        onRate(rating)
                    },
                )
                .simultaneousGesture(TapGesture().onEnded { onSelect() })

                ImageOverlayControlsView(
                    showFocusMask: $interactionState.showFocusMask,
                    focusMaskAvailable: focusMaskAvailable,
                    hasFocusPoints: hasFocusPoints,
                    showFocusPoints: $interactionState.showFocusPoints,
                    showShortcutHints: true,
                    showImageSourceToggle: true,
                    useThumbnailSource: $interactionState.useThumbnailSource,
                    inspectorIsPresented: inspectorIsPresented,
                    onToggleInspector: {
                        onSelect()
                        onToggleInspector()
                    },
                    scale: interactionState.scale,
                    canZoomOut: interactionState.scale > 0.5,
                    canZoomIn: interactionState.scale < 5.0,
                    canReset: interactionState.scale != 1.0 || interactionState.offset != .zero,
                    onZoomOut: {
                        onSelect()
                        decreaseZoom()
                    },
                    onZoomReset: {
                        onSelect()
                        withAnimation(.spring()) { resetToFit() }
                    },
                    onZoomIn: {
                        onSelect()
                        increaseZoom()
                    },
                )
                .simultaneousGesture(TapGesture().onEnded { onSelect() })

                if exifSummary.hasFooterContent {
                    exifFooter
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private var headerOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                if let burstAnalysis, let burstCandidate {
                    BurstCandidateBadgeView(
                        candidate: burstCandidate,
                        analysis: burstAnalysis,
                        rating: burstRating,
                        saliencyLabel: saliencyLabel,
                        isCompact: true,
                    )
                }
                Spacer()
                CurrentRatingBadgeView(rating: rating)
            }

            HStack(alignment: .center, spacing: 8) {
                if let sharpnessContext {
                    sharpnessBadge(for: sharpnessContext)
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 8))
        .padding(8)
    }

    private var zoomPanGesture: AnyGesture<Void> {
        AnyGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { interactionState.scale = interactionState.lastScale * $0 }
                    .onEnded { _ in
                        interactionState.lastScale = interactionState.scale
                        if interactionState.scale < 1.0 {
                            withAnimation(.spring()) { resetToFit() }
                        }
                    },
                DragGesture()
                    .onChanged { value in
                        if interactionState.scale > 1.0 {
                            interactionState.offset = CGSize(
                                width: interactionState.lastOffset.width + value.translation.width,
                                height: interactionState.lastOffset.height + value.translation.height,
                            )
                        }
                    }
                    .onEnded { _ in interactionState.lastOffset = interactionState.offset },
            )
            .map { _ in () },
        )
    }

    private func deltaStyle(for value: Int) -> Color {
        if value > 0 { return .green }
        if value < 0 { return .red }
        return .white.opacity(0.8)
    }

    private func sharpnessBadge(for context: SharpnessComparisonContext) -> some View {
        HStack(spacing: 4) {
            Text(context.rankTitle)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
            if !context.deltaParts.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.55))
                ForEach(Array(context.deltaParts.enumerated()), id: \.element.id) { index, part in
                    if index > 0 {
                        Text("·")
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Text(part.title)
                        .foregroundStyle(deltaStyle(for: part.value))
                }
            }
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
    }

    private var exifFooter: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !exifSummary.exposureParts.isEmpty {
                Text(exifSummary.exposureParts.joined(separator: " · "))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
            if !exifSummary.gearParts.isEmpty {
                Text(exifSummary.gearParts.joined(separator: " · "))
                    .font(.system(size: 10, weight: .medium, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 8))
    }

    @ViewBuilder
    private func imageContent(_ state: ComparisonImageState, in size: CGSize) -> some View {
        if let cgImage = state.cgImage {
            ZStack {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if interactionState.showFocusMask, let focusMask = state.focusMask {
                    Image(decorative: focusMask, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .blendMode(.screen)
                        .opacity(0.95)
                        .transition(.opacity)
                }

                focusPointOverlay(imageSize: CGSize(width: cgImage.width, height: cgImage.height))
            }
            .scaleEffect(interactionState.scale)
            .offset(interactionState.offset)
        } else if let nsImage = state.nsImage {
            ZStack {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                focusPointOverlay(imageSize: nsImage.size)
            }
            .scaleEffect(interactionState.scale)
            .offset(interactionState.offset)
        } else {
            VStack(spacing: 8) {
                if state.isLoading {
                    ProgressView()
                        .fixedSize()
                    Text("Extracting image...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No preview available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func focusPointOverlay(imageSize: CGSize) -> some View {
        if interactionState.showFocusPoints, let focusPoints {
            FocusOverlayView(
                focusPoints: focusPoints,
                imageSize: imageSize,
                markerSize: markerSize,
            )
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }

    private func toggleZoom() {
        withAnimation(.spring()) {
            interactionState.scale > 1.0 ? resetToFit() : zoomToTarget()
        }
    }

    private func resetToFit() {
        interactionState.scale = 1.0
        interactionState.lastScale = 1.0
        interactionState.offset = .zero
        interactionState.lastOffset = .zero
    }

    private func zoomToTarget() {
        interactionState.scale = zoomLevel
        interactionState.lastScale = zoomLevel
        interactionState.offset = .zero
        interactionState.lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            interactionState.scale = min(5.0, interactionState.scale + 0.4)
            interactionState.lastScale = interactionState.scale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            interactionState.scale = max(0.5, interactionState.scale - 0.4)
            interactionState.lastScale = interactionState.scale
        }
    }
}
