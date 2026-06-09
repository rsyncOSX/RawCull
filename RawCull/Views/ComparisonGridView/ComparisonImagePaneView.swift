import RawCullCore
import SwiftUI

struct ComparisonImagePaneView: View {
    let file: FileItem
    let state: ComparisonImageState?
    let focusPoints: [FocusPoint]?
    @Binding var viewportState: ComparisonViewportInteractionState
    @Binding var useThumbnailSource: Bool
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
                Color.black.opacity(0.97)

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
            .contentShape(Rectangle())
            .gesture(zoomPanGesture)
            .onTapGesture(count: 1, perform: onSelect)
            .onTapGesture(count: 2) {
                onSelect()
                toggleZoom()
            }
            .onHover { isHovered = $0 }
            .onChange(of: useThumbnailSource) { _, _ in
                onSourceChange()
            }
            .animation(.easeInOut(duration: 0.16), value: showsPaneChrome)
            .clipped()
        }
        .background(Color.black.opacity(0.97))
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
        VStack(spacing: 0) {
            topOverlay
                .padding(.horizontal, 16)
                .padding(.top, 16)
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
                    showFocusMask: $viewportState.showFocusMask,
                    focusMaskAvailable: focusMaskAvailable,
                    hasFocusPoints: hasFocusPoints,
                    showFocusPoints: $viewportState.showFocusPoints,
                    showShortcutHints: true,
                    showImageSourceToggle: true,
                    useThumbnailSource: $useThumbnailSource,
                    inspectorIsPresented: inspectorIsPresented,
                    onToggleInspector: {
                        onSelect()
                        onToggleInspector()
                    },
                    scale: viewportState.scale,
                    canZoomOut: viewportState.scale > 0.5,
                    canZoomIn: viewportState.scale < 5.0,
                    canReset: viewportState.scale != 1.0 || viewportState.offset != .zero,
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
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var topOverlay: some View {
        HStack(alignment: .top, spacing: 8) {
            CurrentRatingBadgeView(rating: rating)

            VStack(alignment: .leading, spacing: 6) {
                if let burstAnalysis, let burstCandidate {
                    BurstCandidateBadgeView(
                        candidate: burstCandidate,
                        analysis: burstAnalysis,
                        rating: burstRating,
                        saliencyLabel: saliencyLabel,
                        isCompact: true,
                    )
                }

                HStack(alignment: .center, spacing: 8) {
                    if let sharpnessContext {
                        sharpnessBadge(for: sharpnessContext)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text(file.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var zoomPanGesture: AnyGesture<Void> {
        AnyGesture(
            SimultaneousGesture(
                MagnificationGesture()
                    .onChanged { viewportState.scale = viewportState.lastScale * $0 }
                    .onEnded { _ in
                        viewportState.lastScale = viewportState.scale
                        if viewportState.scale < 1.0 {
                            withAnimation(.spring()) { resetToFit() }
                        }
                    },
                DragGesture()
                    .onChanged { value in
                        if viewportState.scale > 1.0 {
                            viewportState.offset = CGSize(
                                width: viewportState.lastOffset.width + value.translation.width,
                                height: viewportState.lastOffset.height + value.translation.height,
                            )
                        }
                    }
                    .onEnded { _ in viewportState.lastOffset = viewportState.offset },
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
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: 560, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func imageContent(_ state: ComparisonImageState, in size: CGSize) -> some View {
        if let cgImage = state.cgImage {
            ZStack {
                Image(decorative: cgImage, scale: 1.0, orientation: .up)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                if viewportState.showFocusMask, let focusMask = state.focusMask {
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
            .scaleEffect(viewportState.scale)
            .offset(viewportState.offset)
        } else if let nsImage = state.nsImage {
            ZStack {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size.width, height: size.height)

                focusPointOverlay(imageSize: nsImage.size)
            }
            .scaleEffect(viewportState.scale)
            .offset(viewportState.offset)
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
        if viewportState.showFocusPoints, let focusPoints {
            FocusOverlayView(
                focusPoints: focusPoints,
                imageSize: imageSize,
            )
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }

    private func toggleZoom() {
        withAnimation(.spring()) {
            viewportState.scale > 1.0 ? resetToFit() : zoomToTarget()
        }
    }

    private func resetToFit() {
        viewportState.resetTransform()
    }

    private func zoomToTarget() {
        viewportState.scale = zoomLevel
        viewportState.lastScale = zoomLevel
        viewportState.offset = .zero
        viewportState.lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            viewportState.scale = min(5.0, viewportState.scale + 0.4)
            viewportState.lastScale = viewportState.scale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            viewportState.scale = max(0.5, viewportState.scale - 0.4)
            viewportState.lastScale = viewportState.scale
        }
    }
}
