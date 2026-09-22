//
//  HistogramPresentationModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 22/09/2026.
//

import Observation
import AppKit
import OSLog

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
