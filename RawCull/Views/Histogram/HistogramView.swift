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

@MainActor
@Observable
final class HistogramLoadingModel {
    typealias ImageConverter = @MainActor (NSImage) -> CGImage?
    typealias Calculator = @Sendable (CGImage) async -> [CGFloat]

    private(set) var normalizedBins: [CGFloat] = []
    private var generation: UInt64 = 0

    func load(
        image: NSImage?,
        convert: ImageConverter,
        calculate: Calculator,
    ) async -> Bool {
        generation &+= 1
        let loadGeneration = generation
        normalizedBins = []

        guard let image, let cgImage = convert(image) else { return false }
        let bins = await calculate(cgImage)
        guard !Task.isCancelled, generation == loadGeneration else { return true }
        normalizedBins = bins
        return true
    }

    @concurrent
    nonisolated static func calculateHistogram(from image: CGImage) async -> [CGFloat] {
        HistogramCalculator.normalizedLuminanceHistogram(from: image)
    }
}

struct HistogramView: View {
    @Binding private var nsImage: NSImage?
    @State private var loader = HistogramLoadingModel()

    init(nsImage: Binding<NSImage?>) {
        _nsImage = nsImage
    }

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
            HistogramPath(bins: loader.normalizedBins)
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
        .frame(height: 150) // Default height
        .task(id: imageIdentity) {
            let converted = await loader.load(
                image: nsImage,
                convert: { image in
                    image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                },
                calculate: HistogramLoadingModel.calculateHistogram,
            )
            if nsImage != nil, !converted {
                Logger.process.warning("HistogramView: could not convert the selected image to CGImage")
            }
        }
    }
}
