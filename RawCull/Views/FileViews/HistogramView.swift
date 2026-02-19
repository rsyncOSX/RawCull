//
//  HistogramView.swift
//  RawCull
//
//  Created by Thomas Evensen on 29/01/2026.
//

import AppKit
import OSLog
import SwiftUI

struct HistogramView: View {
    @Binding var nsImage: NSImage?
    /// We compute the histogram data (0.0 to 1.0) once upon initialization
    @State var normalizedBins: [CGFloat] = []

    // --- View Body ---

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Background color (optional, for dark mode contrast)
                Color.black.opacity(0.2)
                    .cornerRadius(4)

                // The Histogram Path
                HistogramPath(bins: normalizedBins)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // Inset slightly to prevent clipping
                    .padding(2)
            }
        }
        .onChange(of: nsImage) {
            guard let nsImage else { return }
            guard let cgRef = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                Logger.process.warning("Could not initialize CGImage from NSImage")
                return
            }
            Task {
                normalizedBins = await CalculateHistogram().calculateHistogram(from: cgRef)
            }
        }
        .frame(height: 150) // Default height
        .task {
            guard let nsImage else { return }
            guard let cgRef = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("Could not initialize CGImage from NSImage")
            }
            normalizedBins = await CalculateHistogram().calculateHistogram(from: cgRef)
        }
    }
}

// --- Helper Shape for Drawing ---

struct HistogramPath: Shape {
    let bins: [CGFloat]

    func path(in rect: CGRect) -> Path {
        var path = Path()

        guard !bins.isEmpty else { return path }

        let stepX = rect.width / CGFloat(bins.count)

        // Start at bottom left
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))

        for (index, value) in bins.enumerated() {
            let xval = rect.minX + (CGFloat(index) * stepX)
            // Invert Y because 0 is at the top in UIKit/SwiftUI
            let height = rect.height * value
            let yval = rect.maxY - height

            path.addLine(to: CGPoint(x: xval, y: yval))
        }

        // Line to bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        return path
    }
}

/// Make sure that the resource demanding calculation is computed on
/// a background thread
actor CalculateHistogram {
    /// Calculates the luminance histogram and normalizes values to 0.0 - 1.0
    @concurrent
    nonisolated func calculateHistogram(from image: CGImage) async -> [CGFloat] {
        Logger.process.debugThreadOnly("CalculateHistogram: calculateHistogram()")
        let width = image.width
        let height = image.height
        // let totalPixels = width * height

        // 1. Extract raw pixel data
        guard let pixelData = image.dataProvider?.data as Data?,
              let data = CFDataGetBytePtr(pixelData as CFData)
        else {
            return Array(repeating: 0, count: 256)
        }

        var bins = [UInt](repeating: 0, count: 256)
        let bytesPerPixel = image.bitsPerPixel / 8

        // 2. Iterate over pixels and calculate Luminance
        // Standard formula: 0.299 R + 0.587 G + 0.114 B
        for yval in 0 ..< height {
            for xval in 0 ..< width {
                let pixelOffset = (yval * image.bytesPerRow) + (xval * bytesPerPixel)

                let rval = CGFloat(data[pixelOffset])
                let gval = CGFloat(data[pixelOffset + 1])
                let bval = CGFloat(data[pixelOffset + 2])

                // Calculate luminance
                let luminance = 0.299 * rval + 0.587 * gval + 0.114 * bval
                let index = Int(luminance)

                if index >= 0, index < 256 {
                    bins[index] += 1
                }
            }
        }

        // 3. Normalize bins (find the max value and scale everything)
        let maxCount = bins.max() ?? 1
        return bins.map { CGFloat($0) / CGFloat(maxCount) }
    }
}
