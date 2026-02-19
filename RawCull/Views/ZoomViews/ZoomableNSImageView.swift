//
//  ZoomableNSImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 24/01/2026.
//

import SwiftUI

struct ZoomableNSImageView: View {
    /// Use NSImage for macOS
    let nsImage: NSImage?

    // State variables for zoom and pan
    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @Environment(\.dismiss) var dismiss

    private let zoomLevel: CGFloat = 2.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let nsImage {
                GeometryReader { geo in
                    // Image(nsImage:) is the native macOS initializer
                    Image(nsImage: nsImage)
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
            } else {
                HStack {
                    ProgressView()
                        .fixedSize()

                    Text("Loading image...")
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
                    Button(action: { decreaseZoom() }, label: {
                        Image(systemName: "minus.magnifyingglass")
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
                        Image(systemName: "plus.magnifyingglass")
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
                    if let nsImage {
                        Text("\(Int(nsImage.size.width)) × \(Int(nsImage.size.height)) px")
                            .font(.caption2)
                            .foregroundStyle(.black.opacity(0.4))
                    }
                }
                .padding(.bottom, 20)
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
