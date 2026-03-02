//
//  ZoomableFocusePeekNSImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
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

    private let zoomLevel: CGFloat = 2.0

    private var displayedImage: NSImage? {
        showFocusMask ? focusMask : nsImage
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if nsImage != nil {
                GeometryReader { geo in
                    if let image = displayedImage {
                        zoomableImage(image, in: geo.size, isMask: showFocusMask && focusMask != nil)
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
                    toolbarButton("viewfinder.circle.fill") { showFocusMask.toggle() }
                        .disabled(focusMask == nil)
                    toolbarButton("minus.circle.fill") { decreaseZoom() }
                    toolbarButton("xmark.circle") { dismiss() }
                    toolbarButton("plus.circle.fill") { increaseZoom() }
                }
                Spacer()
                VStack(spacing: 8) {
                    Text(currentScale <= 1.0 ? "Double Tap to Zoom" : "Double Tap to Fit Screen")
                        .font(.caption).foregroundStyle(.black.opacity(0.5))
                    if let nsImage {
                        Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                            .font(.caption2).foregroundStyle(.black.opacity(0.4))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: nsImage) {
            await MainActor.run { self.focusMask = nil }
            if let nsImage {
                let mask = await focusDetectorModel.generateFocusMask(from: nsImage, scale: currentScale)
                await MainActor.run { self.focusMask = mask }
            }
        }
    }

    private func zoomableImage(_ image: NSImage, in size: CGSize, isMask: Bool) -> some View {
        Image(nsImage: image)
            .resizable()
            .if(isMask) { $0.opacity(1.0).blendMode(.screen) }
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

/// Handy utility to conditionally apply modifiers
extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}
