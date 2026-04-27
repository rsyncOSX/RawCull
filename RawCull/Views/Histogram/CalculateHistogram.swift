import CoreGraphics
import Foundation
// import OSLog

/// Make sure that the resource demanding calculation is computed on
/// a background thread
actor CalculateHistogram {
    /// Builds a 256-bin luminance histogram from an RGB(A) 8-bit-per-channel image.
    ///
    /// Per-pixel luminance uses the Rec. 601 weighting:
    ///     Y = 0.299·R + 0.587·G + 0.114·B    (R,G,B in 0…255 → Y in 0…255)
    /// Each pixel increments `bins[Int(Y)]`, so `bins[k]` is the raw pixel count
    /// at luminance level `k`.  Before returning, the array is scaled by the
    /// maximum bin value so the result is in `[0, 1]` — ready to be rendered
    /// directly as bar heights in the histogram chart.
    @concurrent
    nonisolated func calculateHistogram(from image: CGImage) async -> [CGFloat] {
        // Logger.process.debugThreadOnly("CalculateHistogram: calculateHistogram()")
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
