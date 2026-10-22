import CoreGraphics
import SwiftUI

/// Display-referred sRGB values, sampled from the completed EV preview.
nonisolated struct RAWExposureHistogram: Sendable {
    let channels: [[CGFloat]]
    let shadowFraction: Double
    let highlightFraction: Double

    @concurrent
    static func calculate(from image: CGImage) async -> Self? {
        guard !Task.isCancelled else { return nil }
        let scale = min(1, 512.0 / Double(max(image.width, image.height)))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
              ), let data = context.data else { return nil }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.assumingMemoryBound(to: UInt8.self)
        var bins = Array(repeating: Array(repeating: CGFloat.zero, count: 256), count: 3)
        var shadows = 0
        var highlights = 0
        for row in 0..<height {
            guard !Task.isCancelled else { return nil }
            for column in 0..<width {
                let offset = (row * width + column) * 4
                var nearBlack = false
                var nearWhite = false
                for channel in 0..<3 {
                    let value = Int(pixels[offset + channel])
                    bins[channel][value] += 1
                    nearBlack = nearBlack || value <= 1
                    nearWhite = nearWhite || value >= 254
                }
                if nearBlack { shadows += 1 }
                if nearWhite { highlights += 1 }
            }
        }
        let peak = max(bins.flatMap { $0 }.max() ?? 1, 1)
        return Self(
            channels: bins.map { $0.map { $0 / peak } },
            shadowFraction: Double(shadows) / Double(width * height),
            highlightFraction: Double(highlights) / Double(width * height)
        )
    }
}

struct RAWExposureHistogramView: View {
    let image: CGImage?
    @State private var histogram: RAWExposureHistogram?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Color.black.opacity(0.35)
                if let histogram {
                    HistogramPath(bins: histogram.channels[0]).fill(.red.opacity(0.5))
                    HistogramPath(bins: histogram.channels[1]).fill(.green.opacity(0.5))
                    HistogramPath(bins: histogram.channels[2]).fill(.blue.opacity(0.5))
                } else {
                    Text(image == nil ? "Waiting for preview…" : "Calculating histogram…")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 72)
            .clipShape(.rect(cornerRadius: 4))
            if let histogram {
                HStack {
                    Text("Near black: \(histogram.shadowFraction, format: .percent.precision(.fractionLength(1)))")
                    Spacer()
                    Text("Near white: \(histogram.highlightFraction, format: .percent.precision(.fractionLength(1)))")
                }
                .monospacedDigit()
            }
            Text("Developed preview · includes tone adjustments · any RGB channel")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("RGB preview histogram")
        .help("Sampled sRGB histogram of the displayed EV preview. Near black: any channel ≤1/255; near white: any channel ≥254/255. This does not measure RAW sensor clipping.")
        .task(id: image.map(ObjectIdentifier.init)) {
            histogram = nil
            guard let image else { return }
            let result = await RAWExposureHistogram.calculate(from: image)
            guard !Task.isCancelled else { return }
            histogram = result
        }
    }
}
