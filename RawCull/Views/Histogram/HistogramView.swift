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
    static let maximumSampleDimension = 512

    @concurrent
    static func calculate(from image: CGImage) async throws -> [CGFloat] {
        try Task.checkCancellation()
        let sampledImage = sampledImage(from: image)
        try Task.checkCancellation()
        let bins = HistogramCalculator.normalizedLuminanceHistogram(from: sampledImage)
        try Task.checkCancellation()
        return bins
    }

    /// Produces a representative image for the display-only histogram without
    /// copying and scanning every pixel in a full-resolution preview.
    static func sampledImage(
        from image: CGImage,
        maximumDimension: Int = maximumSampleDimension,
    ) -> CGImage {
        let boundedMaximumDimension = max(maximumDimension, 1)
        let longestDimension = max(image.width, image.height)
        guard longestDimension > boundedMaximumDimension else { return image }

        let scale = CGFloat(boundedMaximumDimension) / CGFloat(longestDimension)
        let sampleWidth = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let sampleHeight = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        let colorSpace = if image.colorSpace?.model == .rgb {
            image.colorSpace
        } else {
            CGColorSpace(name: CGColorSpace.sRGB)
        }

        guard let colorSpace,
              let context = CGContext(
                  data: nil,
                  width: sampleWidth,
                  height: sampleHeight,
                  bitsPerComponent: 8,
                  bytesPerRow: sampleWidth * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue
                      | CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return image }

        // Preserve representative source values instead of blending color
        // boundaries into luminance values that were not present in the image.
        context.interpolationQuality = .none
        context.draw(
            image,
            in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
        )
        return context.makeImage() ?? image
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
