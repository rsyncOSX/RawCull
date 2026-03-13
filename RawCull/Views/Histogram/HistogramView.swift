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
    @State private var normalizedBins: [CGFloat] = []

    // --- View Body ---

    var body: some View {
        ZStack {
            // Background color (optional, for dark mode contrast)
            Color.black.opacity(0.2)
                .clipShape(.rect(cornerRadius: 4))

            // The Histogram Path
            HistogramPath(bins: normalizedBins)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [.blue, .purple]),
                        startPoint: .top,
                        endPoint: .bottom,
                    ),
                )
                // Inset slightly to prevent clipping
                .padding(2)
        }
        .onChange(of: nsImage) { _, newImage in
            guard let newImage else { return }
            guard let cgRef = newImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
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
