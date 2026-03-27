//
//  FocusOverlayView.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import SwiftUI

// MARK: - Focus Overlay

struct FocusOverlayView: View {
    let focusPoints: [FocusPoint]
    var imageSize: CGSize?
    var markerSize: CGFloat = 64
    var markerColor: Color = .yellow
    var lineWidth: CGFloat = 2.5

    var body: some View {
        // GeometryReader removed: FocusPointMarker is a Shape and receives
        // its rect directly via path(in:) — no proxy needed here.
        ZStack {
            ForEach(focusPoints) { point in
                FocusPointMarker(
                    normalizedX: point.normalizedX,
                    normalizedY: point.normalizedY,
                    boxSize: markerSize,
                    imageSize: imageSize,
                )
                .stroke(markerColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
            }
        }
    }
}

// MARK: - Focus Point Marker Shape (corner brackets)

struct FocusPointMarker: Shape {
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let boxSize: CGFloat
    var imageSize: CGSize?

    /// Returns the actual rendered rect of an aspect-fit image inside a container.
    private func aspectFitRect(imageSize: CGSize, in containerRect: CGRect) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerRect.width / containerRect.height
        if imageAspect > containerAspect {
            // Wider than container → letterbox (bars top & bottom)
            let height = containerRect.width / imageAspect
            let y = containerRect.minY + (containerRect.height - height) / 2
            return CGRect(x: containerRect.minX, y: y, width: containerRect.width, height: height)
        } else {
            // Taller than container → pillarbox (bars left & right)
            let width = containerRect.height * imageAspect
            let x = containerRect.minX + (containerRect.width - width) / 2
            return CGRect(x: x, y: containerRect.minY, width: width, height: containerRect.height)
        }
    }

    func path(in rect: CGRect) -> Path {
        // Use the actual image bounds within the container so the marker aligns
        // correctly regardless of aspect-ratio mismatch (letterbox / pillarbox).
        let drawRect: CGRect = if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            aspectFitRect(imageSize: imageSize, in: rect)
        } else {
            rect
        }

        let cx = drawRect.minX + normalizedX * drawRect.width
        let cy = drawRect.minY + normalizedY * drawRect.height
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
