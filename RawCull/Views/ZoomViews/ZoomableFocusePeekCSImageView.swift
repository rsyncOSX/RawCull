//
//  ZoomableFocusePeekCSImageView.swift
//  RawCull
//

import SwiftUI

struct ZoomableFocusePeekCSImageView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(RawCullViewModel.self) private var viewModel

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    let cgImage: CGImage?

    @State private var focusMask: CGImage?
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showFocusMask: Bool = false
    @State private var showFocusPoints: Bool = false
    @State private var markerSize: CGFloat = 64
    @State private var overlayOpacity: Double = 0.95
    @State private var maskTask: Task<Void, Never>?
    @State private var controlsCollapsed: Bool = false
    @FocusState private var isImageFocused: Bool

    private let zoomLevel: CGFloat = 2.0

    private var slidersVisible: Bool {
        showFocusMask && !controlsCollapsed
    }

    var body: some View {
        @Bindable var vm = viewModel
        ZStack {
            Color.black.ignoresSafeArea()

            if cgImage != nil {
                GeometryReader { geo in
                    ZStack {
                        if let image = cgImage {
                            zoomableImage(image, in: geo.size)
                        }
                        focusPoint()
                    }
                }
            } else {
                HStack {
                    ProgressView().fixedSize()
                    Text("Extracting image…").font(.title)
                }
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }

            VStack {
                HStack {
                    Spacer()
                    toolbarButton("xmark.circle") { dismiss() }
                }

                Spacer()

                VStack(spacing: 8) {
                    Text(currentScale <= 1.0 ? "Double-click to zoom" : "Double-click to fit")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    if let cgImage {
                        Text("\(cgImage.width) × \(cgImage.height) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    ImageOverlayControlsView(
                        showFocusMask: $showFocusMask,
                        config: $vm.sharpnessModel.focusMaskModel.config,
                        overlayOpacity: $overlayOpacity,
                        controlsCollapsed: $controlsCollapsed,
                        focusMaskAvailable: focusMask != nil,
                        hasFocusPoints: focusPoints != nil,
                        showFocusPoints: $showFocusPoints,
                        markerSize: $markerSize,
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
        }
        .focusable()
        .focused($isImageFocused)
        .focusEffectDisabled(true)
        .onKeyPress(characters: CharacterSet(charactersIn: "+-")) { press in
            switch press.characters {
            case "+": increaseZoom(); return .handled
            case "-": decreaseZoom(); return .handled
            default: return .ignored
            }
        }
        .onAppear { isImageFocused = false }
        .onDisappear {
            maskTask?.cancel()
            maskTask = nil
            focusMask = nil
        }
        .task(id: cgImage?.hashValue) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await regenerateMask()
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
        guard let cgImage else { return }
        let downscaled = cgImage.downscaled(toWidth: 1024)
        let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
            from: downscaled ?? cgImage,
            scale: 1.0,
        )
        guard !Task.isCancelled else { return }
        await MainActor.run { self.focusMask = mask }
    }

    // MARK: - Zoomable Image

    private func zoomableImage(_ image: CGImage, in size: CGSize) -> some View {
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
                    .opacity(overlayOpacity)
                    .transition(.opacity)
            }
        }
        .scaleEffect(currentScale)
        .offset(offset)
        .gesture(SimultaneousGesture(
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
        ))
        .onTapGesture(count: 2) {
            withAnimation(.spring()) { currentScale > 1.0 ? resetToFit() : zoomToTarget() }
        }
    }

    // MARK: - Focus Point Overlay

    @ViewBuilder
    private func focusPoint() -> some View {
        if showFocusPoints, let focusPoints, !slidersVisible {
            FocusOverlayView(
                focusPoints: focusPoints,
                imageSize: cgImage.map { CGSize(width: $0.width, height: $0.height) },
                markerSize: markerSize,
            )
            .scaleEffect(currentScale)
            .offset(offset)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }

    // MARK: - Toolbar Button

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

    // MARK: - Zoom Helpers

    private func resetToFit() {
        currentScale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
    }

    private func zoomToTarget() {
        currentScale = zoomLevel; lastScale = zoomLevel; offset = .zero; lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) { currentScale = max(0.5, currentScale + 0.4) }
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
