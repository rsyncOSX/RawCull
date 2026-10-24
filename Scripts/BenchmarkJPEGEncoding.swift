// Diagnostic only: compile with swiftc -O. Does not change the production encoder.
// Compare the current quality-0.7 options allocation with one immutable CFDictionary.
// Inputs are already persisted thumbnails, not RAW extraction or a catalog throughput test.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

func encode(_ image: CGImage, options: CFDictionary?) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
        return nil
    }
    let properties: CFDictionary
    if let options {
        properties = options
    } else {
        let fresh: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        properties = fresh as CFDictionary
    }
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
}

func run() throws {
    guard CommandLine.arguments.count == 2 else {
        throw NSError(domain: "JPEGExperiment", code: 1, userInfo: [NSLocalizedDescriptionKey: "Supply a directory of existing cached JPEGs"])
    }
    let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "jpg" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var images: [CGImage] = []
    var dimensions: [[String: Int]] = []
    for url in urls.prefix(12) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw NSError(domain: "JPEGExperiment", code: 2) }
        images.append(image)
        dimensions.append(["width": image.width, "height": image.height, "bits": image.bitsPerComponent])
    }
    guard images.count == 12 else { throw NSError(domain: "JPEGExperiment", code: 3) }
    let shared = [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary
    // Warm both paths and verify the intervention does not change encoded bytes.
    var bytes = 0
    for image in images {
        guard let first = encode(image, options: nil), let second = encode(image, options: shared), first == second,
              let source = CGImageSourceCreateWithData(first as CFData, nil),
              let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
              decoded.width == image.width, decoded.height == image.height
        else { throw NSError(domain: "JPEGExperiment", code: 4) }
        bytes += first.count
    }
    var trials: [[String: Double]] = []
    let repetitions = 6
    for trial in 0..<12 {
        var result: [String: Double] = [:]
        // Alternate order to reduce systematic warm-up/thermal bias.
        for mode in trial.isMultiple(of: 2) ? ["fresh", "shared"] : ["shared", "fresh"] {
            let start = ProcessInfo.processInfo.systemUptime
            for _ in 0..<repetitions {
                for image in images {
                    let data = autoreleasepool { encode(image, options: mode == "fresh" ? nil : shared) }
                    guard data != nil else { throw NSError(domain: "JPEGExperiment", code: 5) }
                }
            }
            result[mode] = (ProcessInfo.processInfo.systemUptime - start) * 1000 / Double(repetitions * images.count)
        }
        trials.append(result)
    }
    // Time the existing NSImage wrapper round trip separately from encoding.
    var conversion = 0.0
    for image in images {
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<1000 {
            let wrapper = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            guard wrapper.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil else {
                throw NSError(domain: "JPEGExperiment", code: 6)
            }
        }
        conversion += (ProcessInfo.processInfo.systemUptime - start) * 1000
    }
    let fresh = median(trials.compactMap { $0["fresh"] })
    let reused = median(trials.compactMap { $0["shared"] })
    let output: [String: Any] = [
        "quality": 0.7, "images": dimensions, "encoded_bytes_per_pass": bytes,
        "byte_identical_options_variants": true, "trials_ms_per_encode": trials,
        "fresh_median_ms": fresh, "shared_median_ms": reused,
        "shared_change_percent": (reused / fresh - 1) * 100,
        "nsimage_roundtrip_mean_ms": conversion / Double(1000 * images.count),
        "limits": "Sequential diagnostic on 12 decoded persisted thumbnails; not production RAW materialization, orientation/color visual QA, concurrency, or a full-catalog before/after comparison.",
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

do {
    try run()
} catch {
    fputs("JPEG experiment failed: \(error)\n", stderr)
    exit(1)
}
