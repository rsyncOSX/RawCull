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
