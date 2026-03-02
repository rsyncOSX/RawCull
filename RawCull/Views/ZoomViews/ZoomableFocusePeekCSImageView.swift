//
//  ZoomableFocusePeekCSImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
//

import SwiftUI

struct ZoomableFocusePeekCSImageView: View {
    @Environment(\.dismiss) var dismiss
    let cgImage: CGImage?
    let focusPoints: [FocusPoint]?

    @State private var focusMask: CGImage?
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var focusDetectorModel: FocusDetectorMaskModel = .init()
    @State private var showFocusMask: Bool = false
    @State private var showFocusPoints: Bool = false
    @State private var markerSize: CGFloat = 64

    private let zoomLevel: CGFloat = 2.0

    private var displayedImage: CGImage? {
        showFocusMask ? focusMask : cgImage
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cgImage != nil {
                GeometryReader { geo in
                    ZStack {
                        if let image = displayedImage {
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

            // ── All UI chrome in ONE VStack overlay ───────────────────────
            VStack {
                // Top toolbar
                HStack {
                    Spacer()
                    toolbarButton("viewfinder.circle.fill") { showFocusMask.toggle() }
                        .disabled(focusMask == nil)
                    toolbarButton("minus.circle.fill") { decreaseZoom() }
                    toolbarButton("xmark.circle") { dismiss() }
                    toolbarButton("plus.circle.fill") { increaseZoom() }
                }

                Spacer()

                // ✅ Focus point controller — bottom centre, above hint text
                focuspointcontroller

                // Bottom hint text
                VStack(spacing: 8) {
                    Text(currentScale <= 1.0 ? "Double Tap to Zoom" : "Double Tap to Fit Screen")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    if let cgImage {
                        Text("\(cgImage.width) × \(cgImage.height) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: cgImage) {
            await MainActor.run { self.focusMask = nil }
            if let cgImage {
                let downscaled = cgImage.downscaled(toWidth: 1024)
                let mask = await focusDetectorModel.generateFocusMask(from: downscaled ?? cgImage, scale: currentScale)
                await MainActor.run { self.focusMask = mask }
            }
        }
    }

    // MARK: - Zoomable Image

    @ViewBuilder
    private func zoomableImage(_ image: CGImage, in size: CGSize) -> some View {
        Image(decorative: image, scale: 1.0, orientation: .up)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
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
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in lastOffset = offset }
            ))
            .onTapGesture(count: 2) {
                withAnimation(.spring()) { currentScale > 1.0 ? resetToFit() : zoomToTarget() }
            }
    }

    // MARK: - Focus Point Overlay

    @ViewBuilder
    private func focusPoint() -> some View {
        // 2️⃣ Focus overlay on top of image, same scale + offset as the image
        if showFocusPoints, let focusPoints {
            FocusOverlayView(
                focusPoints: focusPoints,
                markerSize: markerSize
            )
            .scaleEffect(currentScale)
            .offset(offset)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .blurReplace))
        }
    }

    // MARK: - Focus Point Control Bar

    private var focuspointcontroller: some View {
        HStack(spacing: 12) {
            // Marker size slider (visible only when focus points are shown)
            if showFocusPoints {
                HStack(spacing: 6) {
                    Image(systemName: "viewfinder")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $markerSize, in: 32 ... 120, step: 4)
                        .frame(width: 100)
                        .controlSize(.small)
                    Image(systemName: "viewfinder")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            // Toggle button — always white so it's visible on black background
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFocusPoints.toggle()
                }
            } label: {
                Image(systemName: showFocusPoints
                    ? "viewfinder.circle.fill"
                    : "viewfinder.circle")
                    .font(.title3)
                    .foregroundStyle(showFocusPoints ? .yellow : .white)  // ← was .primary (black on black!)
                    .symbolEffect(.bounce, value: showFocusPoints)
            }
            .buttonStyle(.plain)
            .help(showFocusPoints ? "Hide focus points" : "Show focus points")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white.opacity(0.15), in: Capsule())  // ← was .ultraThinMaterial (invisible on black)
        .padding(14)
        .animation(.spring(duration: 0.3), value: showFocusPoints)
    }

    // MARK: - Toolbar Button

    @ViewBuilder
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

    private func resetToFit() { currentScale = 1.0; lastScale = 1.0; offset = .zero; lastOffset = .zero }
    private func zoomToTarget() { currentScale = zoomLevel; lastScale = zoomLevel; offset = .zero; lastOffset = .zero }
    private func increaseZoom() { withAnimation(.spring()) { currentScale = max(0.5, currentScale + 0.4) } }
    private func decreaseZoom() { withAnimation(.spring()) { currentScale = max(0.5, currentScale - 0.4) } }
}

extension CGImage {
    func downscaled(toWidth maxWidth: Int) -> CGImage? {
        guard width > maxWidth else { return self }
        let scale = CGFloat(maxWidth) / CGFloat(width)
        let newWidth = maxWidth
        let newHeight = Int(CGFloat(height) * scale)
        guard let context = CGContext(
            data: nil, width: newWidth, height: newHeight,
            bitsPerComponent: bitsPerComponent, bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
