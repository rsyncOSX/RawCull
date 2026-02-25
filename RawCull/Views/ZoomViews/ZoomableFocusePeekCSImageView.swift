//
//  ZoomableFocusePeekCSImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/02/2026.
//

//
//  ZoomableCSImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/01/2026.
//

import SwiftUI

struct ZoomableFocusePeekCSImageView: View {
    @Environment(\.dismiss) var dismiss
    let cgImage: CGImage?

    @State private var focusMask: CGImage? // The image returned by your model

    // State variables for zoom and pan
    @State private var currentScale: CGFloat = 1.0 // Starts zoomed in
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @State private var focusDetectorModel: FocusDetectorMaskModel = .init()
    @State private var showFocusMask: Bool = false

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let cgImage {
                GeometryReader { geo in
                    if showFocusMask, let focusMask {
                        // FIX: Wrapped CGImage in UIImage for proper scaling/orientation
                        Image(decorative: focusMask, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(currentScale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            currentScale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = currentScale
                                            if currentScale < 1.0 {
                                                withAnimation(.spring()) {
                                                    resetToFit()
                                                }
                                            }
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
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if currentScale > 1.0 {
                                        resetToFit()
                                    } else {
                                        zoomToTarget()
                                    }
                                }
                            }
                    } else {
                        // FIX: Wrapped CGImage in UIImage for proper scaling/orientation
                        Image(decorative: cgImage, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(currentScale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            currentScale = lastScale * value
                                        }
                                        .onEnded { _ in
                                            lastScale = currentScale
                                            if currentScale < 1.0 {
                                                withAnimation(.spring()) {
                                                    resetToFit()
                                                }
                                            }
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
                                        .onEnded { _ in
                                            lastOffset = offset
                                        }
                                )
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.spring()) {
                                    if currentScale > 1.0 {
                                        resetToFit()
                                    } else {
                                        zoomToTarget()
                                    }
                                }
                            }
                    }
                }
            } else {
                HStack {
                    ProgressView()
                        .fixedSize()

                    Text("Extracting image, please wait...")
                        .font(.title)
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }

            VStack {
                HStack {
                    Spacer()

                    Button(action: { showFocusMask.toggle() }, label: {
                        Image(systemName: "viewfinder.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Material.ultraThinMaterial)
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .padding()
                    .disabled(focusMask == nil)

                    Button(action: { decreaseZoom() }, label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Material.ultraThinMaterial)
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .padding()

                    Button(action: { dismiss() }, label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Material.ultraThinMaterial)
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .padding()

                    Button(action: { increaseZoom() }, label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Material.ultraThinMaterial)
                            .clipShape(Circle())
                    })
                    .buttonStyle(.plain)
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 2)
                    .padding()
                }
                Spacer()

                VStack(spacing: 8) {
                    if currentScale <= 1.0 {
                        Text("Double Tap to Zoom")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.5))
                    } else {
                        Text("Double Tap to Fit Screen")
                            .font(.caption)
                            .foregroundStyle(.black.opacity(0.5))
                    }
                    if let cgImage {
                        Text("\(cgImage.width) × \(cgImage.height) px")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .task(id: cgImage) {
            await MainActor.run {
                self.focusMask = nil
            } // free memory first
            if let cgImage {
                // Downscale first — the mask doesn't need full resolution
                let downscaled = cgImage.downscaled(toWidth: 1024)

                let mask = await focusDetectorModel.generateFocusMask(
                    from: downscaled ?? cgImage,
                    scale: currentScale
                )
                await MainActor.run {
                    self.focusMask = mask
                }
            }
        }
    }

    private func resetToFit() {
        currentScale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func zoomToTarget() {
        currentScale = zoomLevel
        lastScale = zoomLevel
        offset = .zero
        lastOffset = .zero
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            currentScale = max(0.5, currentScale + 0.4)
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            currentScale = max(0.5, currentScale - 0.4)
        }
    }
}

extension CGImage {
    func downscaled(toWidth maxWidth: Int) -> CGImage? {
        guard width > maxWidth else { return self }
        let scale = CGFloat(maxWidth) / CGFloat(width)
        let newWidth = maxWidth
        let newHeight = Int(CGFloat(height) * scale)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}
