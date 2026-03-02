//
//  FocusPoints.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import SwiftUI

// MARK: - Focus Point Marker Shape (corner brackets)

struct FocusPointMarker: Shape {
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let boxSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = normalizedX * rect.width
        let cy = normalizedY * rect.height
        let half = boxSize / 2
        let bracket = boxSize * 0.28

        var path = Path()

        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-1, -1, 1, 0), (-1, -1, 0, 1),
            (1, -1, -1, 0), (1, -1, 0, 1),
            (-1, 1, 1, 0), (-1, 1, 0, -1),
            (1, 1, -1, 0), (1, 1, 0, -1)
        ]

        for (sx, sy, dx, dy) in corners {
            path.move(to: CGPoint(x: cx + sx * half, y: cy + sy * half))
            path.addLine(to: CGPoint(x: cx + sx * half + dx * bracket,
                                     y: cy + sy * half + dy * bracket))
        }
        return path
    }
}

// MARK: - Focus Overlay

struct FocusOverlayView: View {
    let focusPoints: [FocusPoint]
    var markerSize: CGFloat = 64
    var markerColor: Color = .yellow
    var lineWidth: CGFloat = 2.5

    var body: some View {
        GeometryReader { _ in
            ZStack {
                ForEach(focusPoints) { point in
                    FocusPointMarker(
                        normalizedX: point.normalizedX,
                        normalizedY: point.normalizedY,
                        boxSize: markerSize
                    )
                    .stroke(markerColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
                }
            }
        }
    }
}

// MARK: - Main Image + Focus View

struct FocusImageView: View {
    let image: NSImage
    let focusPoints: [FocusPoint]

    @State private var showFocusPoints = true
    @State private var markerSize: CGFloat = 64
    @State private var isHoveringToggle = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ── Image + overlay ──────────────────────────────────────
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()

                if showFocusPoints {
                    FocusOverlayView(
                        focusPoints: focusPoints,
                        markerSize: markerSize
                    )
                    .transition(.opacity.combined(with: .blurReplace))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showFocusPoints)

            // ── macOS 26 glass control bar ───────────────────────────
            HStack(spacing: 12) {
                // Marker size slider
                if showFocusPoints {
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $markerSize, in: 32 ... 120, step: 4)
                            .frame(width: 100)
                            .controlSize(.small)
                        Image(systemName: "viewfinder")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Toggle button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFocusPoints.toggle()
                    }
                } label: {
                    Image(systemName: showFocusPoints
                        ? "viewfinder.circle.fill"
                        : "viewfinder.circle")
                        .font(.title3)
                        .symbolEffect(.bounce, value: showFocusPoints)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showFocusPoints ? .yellow : .primary)
                .help(showFocusPoints ? "Hide focus points" : "Show focus points")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(14)
            .animation(.spring(duration: 0.3), value: showFocusPoints)
        }
    }
}

// MARK: - Gallery / Browser View

struct FocusGalleryView: View {
    let items: [FocusPointsModel]

    /// Wire this up to your actual thumbnail loader
    var imageLoader: (FocusPointsModel) -> NSImage = { _ in
        NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!
    }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320), spacing: 16)],
                spacing: 16
            ) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        FocusImageView(
                            image: imageLoader(item),
                            focusPoints: item.focusPoints
                        )
                        .aspectRatio(3 / 2, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)

                        Text(item.sourceFile)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Focus Points")
    }
}

// ── Thumbnail in grid ────────────────────────────────────────────────

struct ThumbnailCell: View {
    let item: FocusPointsModel
    let image: NSImage

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()

            FocusOverlayView(
                focusPoints: item.focusPoints,
                markerSize: .focusMarkerThumbnail,
                lineWidth: 1
            )
        }
        .aspectRatio(3 / 2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// ── Extracted JPG detail / full viewer ───────────────────────────────

struct DetailImageView: View {
    let item: FocusPointsModel
    let image: NSImage

    @State private var showFocusPoints = true
    @State private var markerSize: CGFloat = .focusMarkerFullscreen

    var body: some View {
        ZStack {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()

            if showFocusPoints {
                FocusOverlayView(
                    focusPoints: item.focusPoints,
                    markerSize: markerSize,
                    lineWidth: 2.5
                )
                .transition(.opacity.combined(with: .blurReplace))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showFocusPoints)
    }
}

// MARK: - Preview

#Preview("Single image") {
    FocusImageView(
        image: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)!,
        focusPoints: [
            FocusPoint(focusLocation: "8640 5760 3523 2712")!,
            FocusPoint(focusLocation: "8640 5760 3820 2928")!
        ]
    )
    .frame(width: 900, height: 620)
}

#Preview("Gallery") {
    FocusGalleryView(items: [
        FocusPointsModel(sourceFile: "_DSC8879.ARW", focusLocations: ["8640 5760 3523 2712"]),
        FocusPointsModel(sourceFile: "_DSC8911.ARW", focusLocations: ["8640 5760 3820 2928"])
    ])
    .frame(width: 900, height: 620)
}

//
//  FocusPointsModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/02/2026.
//

// MARK: - In-memory focus point store

@Observable
final class FocusPointStore {
    private(set) var data: [String: [FocusPoint]] = [:] // keyed by sourceFile

    var loadedCount: Int {
        data.count
    }

    func store(focusData: FocusPointsModel) {
        data[focusData.sourceFile] = focusData.focusPoints
    }

    func focusPoints(for sourceFile: String) -> [FocusPoint]? {
        data[sourceFile] // nil = not yet scanned, trigger rescan
    }

    func remove(for sourceFile: String) {
        data.removeValue(forKey: sourceFile)
    }

    func removeAll() {
        data.removeAll()
    }

    /// Approximate memory footprint for diagnostics
    var estimatedBytes: Int {
        let pointBytes = data.values.reduce(0) { $0 + $1.count * 48 }
        let keyBytes = data.keys.reduce(0) { $0 + $1.utf8.count + 50 }
        return pointBytes + keyBytes
    }
}

/*
 swift// In your scanning / thumbnail pipeline
 if store.focusPoints(for: sourceFile) == nil {
     // trigger exiftool rescan for this file
 }

 exiftool -Sony:FocusLocation *.ARW -j
 [{
   "SourceFile": "_DSC8879.ARW",
   "FocusLocation": "8640 5760 3523 2712"
 },
 {
   "SourceFile": "_DSC8911.ARW",
   "FocusLocation": "8640 5760 3820 2928"
 }]
 */
