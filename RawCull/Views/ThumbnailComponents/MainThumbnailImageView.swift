import SwiftUI

struct MainThumbnailImageView: View {
    @Environment(RawCullViewModel.self) private var viewModel
    @Environment(SettingsViewModel.self) private var settings

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    let url: URL
    let file: FileItem?

    @State private var image: NSImage?
    @State private var thumbnailSizePreview: Int?

    @State private var showFocusPoints = false
    @State private var markerSize: CGFloat = 40

    // Focus mask state
    @State private var focusMask: NSImage?
    @State private var showFocusMask: Bool = false
    @State private var overlayOpacity: Double = 0.85
    @State private var focusDetectorModel = FocusMaskModel()
    @State private var maskTask: Task<Void, Never>?
    @State private var controlsCollapsed: Bool = false
    @FocusState private var isImageFocused: Bool

    private var focusMaskSlidersVisible: Bool {
        showFocusMask && !controlsCollapsed
    }

    var body: some View {
        ZStack {
            if let thumbnailSizePreview {
                VStack {
                    GeometryReader { geo in
                        ZStack {
                            // 1️⃣ Image FIRST (background)
                            ThumbnailImageView(
                                url: url,
                                targetSize: thumbnailSizePreview,
                                style: .list,
                                showsShimmer: false,
                                contentMode: .fit,
                                image: $image,
                            )
                            .scaleEffect(scale)
                            .offset(offset)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        scale = lastScale * value.magnification
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    },
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if scale > 1.0 {
                                            offset = CGSize(
                                                width: value.translation.width,
                                                height: value.translation.height,
                                            )
                                        }
                                    }
                                    .onEnded { _ in },
                            )

                            // 2️⃣ Focus mask overlay

                            if showFocusMask, let mask = focusMask {
                                Image(nsImage: mask)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .scaleEffect(scale)
                                    .offset(offset)
                                    .blendMode(.screen)
                                    .opacity(overlayOpacity)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                            

                            // 3️⃣ Focus points overlay
                            if showFocusPoints, let focusPoints, !focusMaskSlidersVisible {
                                FocusOverlayView(
                                    focusPoints: focusPoints,
                                    markerSize: markerSize,
                                )
                                .scaleEffect(scale)
                                .offset(offset)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .blurReplace))
                            }

                            VStack {
                                // File metadata at the top where it belongs
                                if let file, !focusMaskSlidersVisible {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.name)
                                                .font(.headline)
                                            Text(file.url.deletingLastPathComponent().path())
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial)
                                    .clipShape(.rect(cornerRadius: 8))
                                    .padding([.top, .horizontal], 8)
                                }

                                Spacer()

                                ImageOverlayControlsView(
                                    showFocusMask: $showFocusMask,
                                    config: $focusDetectorModel.config,
                                    overlayOpacity: $overlayOpacity,
                                    controlsCollapsed: $controlsCollapsed,
                                    focusMaskAvailable: focusMask != nil,
                                    hasFocusPoints: focusPoints != nil,
                                    showFocusPoints: $showFocusPoints,
                                    markerSize: $markerSize,
                                    scale: viewModel.scale,
                                    canZoomOut: viewModel.scale > 0.5,
                                    canZoomIn: viewModel.scale < 4.0,
                                    canReset: viewModel.scale != 1.0 || viewModel.offset != .zero,
                                    onZoomOut: { withAnimation(.spring()) { viewModel.scale = max(0.5, viewModel.scale - 0.2) } },
                                    onZoomReset: { withAnimation(.spring()) { viewModel.resetZoom() } },
                                    onZoomIn: { withAnimation(.spring()) { viewModel.scale = min(4.0, viewModel.scale + 0.2) } },
                                )
                                .padding(.bottom, 12)
                            }
                        }
                        .focusable()
                        .focused($isImageFocused)
                        .focusEffectDisabled()
                        .onKeyPress(characters: CharacterSet(charactersIn: "+-")) { press in
                            switch press.characters {
                            case "+":
                                withAnimation(.spring()) {
                                    scale = min(4.0, scale + 0.2)
                                    lastScale = scale
                                }
                                return .handled
                            case "-":
                                withAnimation(.spring()) {
                                    scale = max(0.5, scale - 0.2)
                                    lastScale = scale
                                }
                                return .handled
                            default:
                                return .ignored
                            }
                        }
                        .onAppear { isImageFocused = true }
                    }
                }
                .shadow(radius: 4)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(.rect(cornerRadius: 8))
            } else {
                ProgressView()
                    .fixedSize()
            }
        }
        .task {
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            thumbnailSizePreview = settingsmanager.thumbnailSizePreview
        }
        .task(id: image) {
            if let image {
                let mask = await focusDetectorModel.generateFocusMask(from: image, scale: 1.0)
                await MainActor.run { self.focusMask = mask }
            }
        }
        .onChange(of: focusDetectorModel.config) { _, _ in
            maskTask?.cancel()
            maskTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await regenerateMask()
            }
        }
    }

    // MARK: - Regenerate Mask

    private func regenerateMask() async {
        guard let image else { return }
        let mask = await focusDetectorModel.generateFocusMask(from: image, scale: 1.0)
        await MainActor.run { self.focusMask = mask }
    }
}
