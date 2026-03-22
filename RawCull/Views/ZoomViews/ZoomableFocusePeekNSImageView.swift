//
//  ZoomableFocusePeekNSImageView.swift
//  RawCull
//

import SwiftUI

struct ZoomableFocusePeekNSImageView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(RawCullViewModel.self) private var viewModel

    let nsImage: NSImage?

    private var focusPoints: [FocusPoint]? {
        viewModel.getFocusPoints()
    }

    @State private var focusMask: NSImage?
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var focusDetectorModel = FocusMaskModel()
    @State private var showFocusPoints: Bool = false
    @State private var markerSize: CGFloat = 64
    @State private var showFocusMask: Bool = false
    @State private var overlayOpacity: Double = 0.85
    @State private var maskTask: Task<Void, Never>?
    @State private var controlsCollapsed: Bool = false // ← new

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if nsImage != nil {
                GeometryReader { geo in
                    if let image = nsImage {
                        zoomableImage(image, in: geo.size)
                    }

                    focusPoint()
                }
            } else {
                HStack {
                    ProgressView().fixedSize()
                    Text("Loading image...").font(.title)
                }
                .padding()
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }

            VStack {
                HStack {
                    Spacer()

                    if focusPoints != nil {
                        FocusPointControllerView(
                            showFocusPoints: $showFocusPoints,
                            markerSize: $markerSize,
                        )
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
                    Text(currentScale <= 1.0 ? "Double-click to zoom" : "Double-click to fit")
                        .font(.caption).foregroundStyle(.white.opacity(0.5))
                    if let nsImage {
                        Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    FocusMaskControlsView(
                        showFocusMask: $showFocusMask,
                        config: $focusDetectorModel.config,
                        overlayOpacity: $overlayOpacity,
                        controlsCollapsed: $controlsCollapsed,
                        focusMaskAvailable: focusMask != nil,
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: nsImage) {
            if let nsImage {
                let mask = await focusDetectorModel.generateFocusMask(from: nsImage, scale: 1.0)
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

    // MARK: - Regenerate Mask

    private func regenerateMask() async {
        guard let nsImage else { return }
        let mask = await focusDetectorModel.generateFocusMask(from: nsImage, scale: 1.0)
        await MainActor.run { self.focusMask = mask }
    }

    // MARK: - Zoomable Image

    private func zoomableImage(_ image: NSImage, in size: CGSize) -> some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size.width, height: size.height)

            if showFocusMask, let mask = focusMask {
                Image(nsImage: mask)
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
