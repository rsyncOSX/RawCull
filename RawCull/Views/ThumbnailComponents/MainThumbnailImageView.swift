import SwiftUI

struct MainThumbnailImageView: View {
    @Environment(RawCullViewModel.self) private var viewModel

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    let url: URL
    let file: FileItem?

    @State private var image: NSImage?
    @State private var thumbnailSizePreview: Int?

    @State private var showFocusPoints = false

    // Focus mask state
    @State private var focusMask: NSImage?
    @State private var showFocusMask: Bool = false
    @State private var maskTask: Task<Void, Never>?
    @FocusState private var isImageFocused: Bool

    var body: some View {
        @Bindable var vm = viewModel
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
                            .scaleEffect(viewModel.scale)
                            .offset(viewModel.offset)
                            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                            .gesture(
                                MagnifyGesture()
                                    .onChanged { value in
                                        viewModel.scale = viewModel.lastScale * value.magnification
                                    }
                                    .onEnded { _ in
                                        viewModel.lastScale = viewModel.scale
                                    },
                            )
                            .simultaneousGesture(
                                DragGesture()
                                    .onChanged { value in
                                        if viewModel.scale > 1.0 {
                                            viewModel.offset = CGSize(
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
                                    .scaleEffect(viewModel.scale)
                                    .offset(viewModel.offset)
                                    .blendMode(.screen)
                                    .opacity(0.95)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }

                            // 3️⃣ Focus points overlay
                            if showFocusPoints, let focusPoints {
                                FocusOverlayView(
                                    focusPoints: focusPoints,
                                    imageSize: image?.size,
                                    markerSize: viewModel.focusPointMarkerSize,
                                )
                                .scaleEffect(viewModel.scale)
                                .offset(viewModel.offset)
                                .allowsHitTesting(false)
                                .transition(.opacity.combined(with: .blurReplace))
                            }

                            VStack {
                                // File metadata at the top where it belongs
                                if let file {
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
                                    focusMaskAvailable: focusMask != nil,
                                    hasFocusPoints: focusPoints != nil,
                                    showFocusPoints: $showFocusPoints,
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
                        .focusEffectDisabled(true)
                        .onKeyPress(characters: CharacterSet(charactersIn: "+-")) { press in
                            switch press.characters {
                            case "+":
                                withAnimation(.spring()) {
                                    viewModel.scale = min(4.0, viewModel.scale + 0.2)
                                    viewModel.lastScale = viewModel.scale
                                }
                                return .handled

                            case "-":
                                withAnimation(.spring()) {
                                    viewModel.scale = max(0.5, viewModel.scale - 0.2)
                                    viewModel.lastScale = viewModel.scale
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
                let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(from: image, scale: 1.0)
                await MainActor.run { self.focusMask = mask }
            }
        }
        .onChange(of: viewModel.sharpnessModel.focusMaskModel.config) { _, _ in
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
        let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(from: image, scale: 1.0)
        await MainActor.run { self.focusMask = mask }
    }
}
