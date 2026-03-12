import SwiftUI

struct MainCachedThumbnailView: View {
    @Environment(RawCullViewModel.self) private var viewModel

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize

    let url: URL

    @State private var image: NSImage?
    @State private var isLoading = false

    @State private var showFocusPoints = false
    @State private var markerSize: CGFloat = 40

    // Focus mask state
    @State private var focusMask: NSImage?
    @State private var showFocusMask: Bool = false
    @State private var overlayOpacity: Double = 0.85
    @State private var focusDetectorModel = FocusDetectorMaskModel()
    @State private var maskTask: Task<Void, Never>?
    @State private var controlsCollapsed: Bool = false

    var body: some View {
        ZStack {
            if let image {
                VStack {
                    GeometryReader { geo in
                        ZStack {
                            // 1️⃣ Image FIRST (background)
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .scaleEffect(scale)
                                .offset(offset)
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
                                .gesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = lastScale * value
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
                            if showFocusPoints, let focusPoints {
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
                                Spacer()
                                VStack(spacing: 8) {
                                    if showFocusMask {
                                        FocusMaskControlsView(
                                            config: $focusDetectorModel.config,
                                            overlayOpacity: $overlayOpacity,
                                            controlsCollapsed: $controlsCollapsed,
                                        )
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                    }

                                    focuspointcontroller
                                }
                            }
                        }
                    }
                }
                .shadow(radius: 4)
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            } else if isLoading {
                ProgressView()
                    .fixedSize()
            } else {
                ContentUnavailableView("Select an Image", systemImage: "photo")
            }
        }
        .task(id: url) {
            isLoading = true
            let settingsmanager = await SettingsViewModel.shared.asyncgetsettings()
            let thumbnailSizePreview = settingsmanager.thumbnailSizePreview
            let cgImage = await RequestThumbnail().requestThumbnail(
                for: url,
                targetSize: thumbnailSizePreview,
            )
            if let cgImage {
                image = NSImage(cgImage: cgImage, size: .zero)
            } else {
                image = nil
            }
            isLoading = false
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

    // MARK: - Focus Point Control Bar

    private var focuspointcontroller: some View {
        HStack(spacing: 12) {
            if showFocusPoints {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $markerSize, in: 32 ... 100, step: 4)
                        .frame(width: 100)
                        .controlSize(.small)
                    Image(systemName: "viewfinder")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Focus mask toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusMask.toggle() }
            } label: {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.title3)
                    .foregroundStyle(showFocusMask ? .blue : .primary)
                    .symbolEffect(.bounce, value: showFocusMask)
            }
            .buttonStyle(.plain)
            .disabled(focusMask == nil)
            .help(showFocusMask ? "Hide focus mask" : "Show focus mask")

            // Focus points toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFocusPoints.toggle()
                }
            } label: {
                Image(systemName: showFocusPoints
                    ? "viewfinder.circle.fill"
                    : "viewfinder.circle")
                    .font(.title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .primary)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
        }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }

    // MARK: - Regenerate Mask

    private func regenerateMask() async {
        guard let image else { return }
        let mask = await focusDetectorModel.generateFocusMask(from: image, scale: 1.0)
        await MainActor.run { self.focusMask = mask }
    }
}
