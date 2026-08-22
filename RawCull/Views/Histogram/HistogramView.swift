//
//  HistogramView.swift
//  RawCull
//
//  Created by Thomas Evensen on 29/01/2026.
//

import AppKit
import OSLog
import RawCullCore
import SwiftUI

nonisolated enum HistogramLoader {
    typealias Calculator = @Sendable (CGImage) async throws -> [CGFloat]

    @concurrent
    static func calculate(from image: CGImage) async throws -> [CGFloat] {
        try Task.checkCancellation()
        let bins = HistogramCalculator.normalizedLuminanceHistogram(from: image)
        try Task.checkCancellation()
        return bins
    }
}

@MainActor
@Observable
final class HistogramPresentationModel {
    private(set) var normalizedBins: [CGFloat] = []

    func load(
        image: NSImage?,
        calculate: HistogramLoader.Calculator = HistogramLoader.calculate,
    ) async {
        guard let image else {
            normalizedBins = []
            return
        }
        guard let cgImage = image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil,
        ) else {
            normalizedBins = []
            Logger.process.warning("Could not initialize CGImage from NSImage")
            return
        }

        do {
            let bins = try await calculate(cgImage)
            try Task.checkCancellation()
            normalizedBins = bins
        } catch is CancellationError {
            // A newer image owns publication after SwiftUI cancels this task.
        } catch {
            guard !Task.isCancelled else { return }
            normalizedBins = []
            Logger.process.warning(
                "Could not calculate image histogram: \(String(describing: error), privacy: .public)",
            )
        }
    }
}

struct HistogramView: View {
    let nsImage: NSImage?
    var height: CGFloat = 150
    @State private var presentation = HistogramPresentationModel()

    private var imageIdentity: ObjectIdentifier? {
        nsImage.map(ObjectIdentifier.init)
    }

    // --- View Body ---

    var body: some View {
        ZStack {
            // Background color (optional, for dark mode contrast)
            Color.black.opacity(0.2)
                .clipShape(.rect(cornerRadius: 4))

            // The Histogram Path
            HistogramPath(bins: presentation.normalizedBins)
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
        .frame(height: height)
        .task(id: imageIdentity) {
            await presentation.load(image: nsImage)
        }
    }
}
