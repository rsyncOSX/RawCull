//
//  ZoomableFocusePeekNSImageView.swift
//  RawCull
//

import SwiftUI

struct ZoomableFocusePeekNSImageView: View {
    @Environment(\.dismiss) var dismiss
    let nsImage: NSImage?

    @State private var focusMask: NSImage?
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var focusDetectorModel: FocusDetectorMaskModel = .init()
    @State private var showFocusMask: Bool = false
    @State private var overlayOpacity: Double = 0.85
    @State private var maskTask: Task<Void, Never>?

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if nsImage != nil {
                GeometryReader { geo in
                    if let image = nsImage {
                        zoomableImage(image, in: geo.size)
                    }
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
                    if let nsImage {
                        Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }

                    if showFocusMask {
                        focusMaskControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
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

    // MARK: - Focus Mask Controls

    private var focusMaskControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Focus Mask")
                    .font(.headline)
                Spacer()
                Button("Reset") {
                    focusDetectorModel.config = FocusDetectorConfig()
                    overlayOpacity = 0.85
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LabeledSlider(
                label: "Threshold",
                value: $focusDetectorModel.config.threshold,
                range: 0.10 ... 0.50,
                hint: "Lower = more highlighted, Higher = only sharpest edges"
            )

            LabeledSlider(
                label: "Pre-blur",
                value: $focusDetectorModel.config.preBlurRadius,
                range: 0.5 ... 2.5,
                hint: "Higher = ignore more background texture"
            )

            LabeledSlider(
                label: "Amplify",
                value: $focusDetectorModel.config.energyMultiplier,
                range: 4.0 ... 20.0,
                hint: "Amplification of sharpness signal"
            )

            LabeledSlider(
                label: "Overlay",
                value: Binding(
                    get: { Float(overlayOpacity) },
                    set: { overlayOpacity = Double($0) }
                ),
                range: 0.3 ... 1.0,
                hint: "Overlay strength"
            )
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
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
