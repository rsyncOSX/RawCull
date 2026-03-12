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
    @State private var focusDetectorModel = FocusDetectorMaskModel()
    @State private var showFocusMask: Bool = false
    @State private var showFocusPoints: Bool = false
    @State private var markerSize: CGFloat = 64
    @State private var overlayOpacity: Double = 0.85
    @State private var maskTask: Task<Void, Never>?
    @State private var controlsCollapsed: Bool = false // ← new

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
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
                    Text("Extracting image, please wait...").font(.title)
                }
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }

            VStack {
                HStack {
                    Spacer()
                    
                    if focusPoints != nil {
                        focuspointcontroller
                    }

                    toolbarButton("viewfinder.circle.fill") {
                        withAnimation(.easeInOut(duration: 0.2)) { showFocusMask.toggle() }
                    }
                    .disabled(focusMask == nil)

                    toolbarButton("minus.circle.fill") { decreaseZoom() }
                    toolbarButton("xmark.circle") { dismiss() }
                    toolbarButton("plus.circle.fill") { increaseZoom() }
                }

                Spacer()

                VStack(spacing: 8) {
                    Text(currentScale <= 1.0 ? "Double Tap to Zoom" : "Double Tap to Fit Screen")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    if let cgImage {
                        Text("\(cgImage.width) × \(cgImage.height) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    if showFocusMask {
                        FocusMaskControlsView(
                            config: $focusDetectorModel.config,
                            overlayOpacity: $overlayOpacity,
                            controlsCollapsed: $controlsCollapsed,
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: cgImage?.hashValue) {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await regenerateMask()
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
        guard let cgImage else { return }
        let downscaled = cgImage.downscaled(toWidth: 1024)
        let mask = await focusDetectorModel.generateFocusMask(
            from: downscaled ?? cgImage,
            scale: 1.0,
        )
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
        if showFocusPoints, let focusPoints {
            FocusOverlayView(focusPoints: focusPoints, markerSize: markerSize)
                .scaleEffect(currentScale)
                .offset(offset)
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .blurReplace))
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

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFocusPoints.toggle() }
            } label: {
                Image(systemName: showFocusPoints ? "viewfinder.circle.fill" : "viewfinder.circle")
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
        .overlay { Capsule().strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(10)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }

    // MARK: - Toolbar Button

    private func toolbarButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Material.ultraThinMaterial)
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
