// Diagnostic only. Compile alongside the production GridThumbnailResizer.swift.
// Compares normalized persisted JPEGs, not RAW extraction or catalog throughput.
import AppKit
import Foundation
import ImageIO

@main
struct GridPreparationDiagnostic {
    static func source(_ url: URL) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyOrientation] as? Int ?? 1) == 1
        else { throw CocoaError(.fileReadCorruptFile) }
        return source
    }

    static func grid(_ url: URL, downsample: Bool) throws -> CGImage {
        let source = try source(url)
        if downsample {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 200,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return image
        }
        let options = [kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false] as CFDictionary
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options),
              let resized = GridThumbnailResizer.resize(NSImage(cgImage: image, size: .zero), source: image),
              let bitmap = resized.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { throw CocoaError(.fileReadCorruptFile) }
        return bitmap
    }

    static func pixels(_ image: CGImage) throws -> [UInt8] {
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw CocoaError(.coderInvalidValue) }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: CommandLine.arguments[1]), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }
        guard urls.count >= 12 else { throw CocoaError(.fileReadNoSuchFile) }
        // Evenly spaced across the sorted cache, bounded to avoid retaining large previews.
        let sample = (0..<12).map { urls[$0 * (urls.count - 1) / 11] }
        var comparisons: [[String: Any]] = []
        for url in sample {
            try autoreleasepool {
                let current = try grid(url, downsample: false)
                let candidate = try grid(url, downsample: true)
                let sameDimensions = current.width == candidate.width && current.height == candidate.height
                var result: [String: Any] = ["file": url.lastPathComponent,
                    "currentWidth": current.width, "currentHeight": current.height,
                    "candidateWidth": candidate.width, "candidateHeight": candidate.height,
                    "sameDimensions": sameDimensions]
                if sameDimensions {
                    let first = try pixels(current), second = try pixels(candidate)
                    let differences = zip(first, second).enumerated().filter { $0.offset % 4 != 3 }
                        .map { abs(Int($0.element.0) - Int($0.element.1)) }
                    result["meanAbsoluteChannelDifference"] = Double(differences.reduce(0, +)) / Double(differences.count)
                    result["maxChannelDifference"] = differences.max()!
                }
                comparisons.append(result)
            }
        }
        var rounds: [[String: Double]] = []
        for round in 0..<12 {
            var result: [String: Double] = [:]
            for downsample in (round.isMultiple(of: 2) ? [false, true] : [true, false]) {
                let start = ProcessInfo.processInfo.systemUptime
                for _ in 0..<6 {
                    for url in sample {
                        try autoreleasepool {
                            let image = try grid(url, downsample: downsample)
                            guard image.width > 0 && image.height > 0 else { throw CocoaError(.fileReadCorruptFile) }
                        }
                    }
                }
                result[downsample ? "downsampleMS" : "currentMS"] =
                    (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(sample.count * 6)
            }
            rounds.append(result)
        }
        let output: [String: Any] = ["comparisons": comparisons, "rounds": rounds,
            "notes": "12 normalized cached JPEGs; alternating order; six passes per round; warm OS caches; sequential; includes source properties in both paths; quality is not validated by pixel error"]
        let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
