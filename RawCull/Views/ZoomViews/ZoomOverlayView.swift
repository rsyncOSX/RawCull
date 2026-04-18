//
//  ZoomOverlayView.swift
//  RawCull
//
//  Full-window zoom overlay. Replaces the older separate zoom windows by
//  covering the main window in a ZStack above the normal content. Dismiss
//  via Escape, the close button, or a second double-tap.
//

import SwiftUI

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
    @State private var maskTask: Task<Void, Never>?
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
                    Spacer()
                    toolbarButton("xmark.circle") { dismiss() }
                }

                Spacer()

                VStack(spacing: 8) {
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
        .onKeyPress(characters: CharacterSet(charactersIn: "+-")) { press in
            switch press.characters {
            case "+": increaseZoom(); return .handled
            case "-": decreaseZoom(); return .handled
            default: return .ignored
            }
        }
        .onAppear { isImageFocused = true }
        .onDisappear {
            maskTask?.cancel()
            maskTask = nil
            focusMask = nil
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

    // MARK: - Dismiss

    private func dismiss() {
        viewModel.zoomExtractionTask?.cancel()
        viewModel.zoomExtractionTask = nil
        viewModel.zoomOverlayVisible = false
        viewModel.zoomOverlayCGImage = nil
        viewModel.zoomOverlayNSImage = nil
        resetToFit()
        focusMask = nil
    }

    // MARK: - Mask regeneration

    private func regenerateMaskFromCG() async {
        guard let cg = viewModel.zoomOverlayCGImage else { return }
        let downscaled = cg.downscaled(toWidth: 1024)
        let mask = await viewModel.sharpnessModel.focusMaskModel.generateFocusMask(
            from: downscaled ?? cg,
            scale: 1.0,
        )
        guard !Task.isCancelled else { return }
        await MainActor.run { self.focusMask = mask }
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

    // MARK: - Zoom helpers

    private func resetToFit() {
        currentScale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero
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
