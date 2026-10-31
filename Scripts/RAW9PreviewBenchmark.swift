// Compiled together with the production RAWPreviewRenderer.swift by RunRAW9PreviewBenchmark.py.
import CoreImage
import Foundation
import ImageIO
import RawParserKit
import Darwin

@main struct RAW9PreviewBenchmark {
    static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let mode = CommandLine.arguments[2]
        let limit = Int(CommandLine.arguments[3])!
        let passes = Int(CommandLine.arguments[4])!
        let scratch = URL(fileURLWithPath: CommandLine.arguments[5])
        let files = Array(try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "arw" }.sorted { $0.path < $1.path }.prefix(limit))
        guard !files.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        let renderer = RAWPreviewRenderer(cacheByteLimit: 256 * 1024 * 1024)
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAh])
        for pass in 0..<passes {
            for url in files {
                let supported = autoreleasepool {
                    CIRAWFilter(imageURL: url)?.supportedDecoderVersions.contains(.version9) == true
                }
                guard supported else { throw BenchmarkError.unsupportedRAW9(url.lastPathComponent) }
                if mode != "revisit" { await renderer.clearCache() }
                if mode == "revisit" { _ = try await renderer.render(url: url, maximumDimension: 3072) }
                let start = ContinuousClock.now
                var stages: [String: Any] = [:]
                let image: CGImage
                if mode == "baseline" || mode == "native" {
                    let data = try await SonyRawFormat.createFullSizeJPEG(from: url, quality: 1, useRAW9: true)
                    let encoded = ContinuousClock.now
                    let decodedImage = try requireImage(OrientationNormalizedImageLoader.loadCGImage(from: data))
                    image = decodedImage
                    let decoded = ContinuousClock.now
                    try data.write(to: scratch.appendingPathComponent("legacy-cache.jpg"), options: .atomic)
                    let saved = ContinuousClock.now
                    stages["encode_ms"] = ms(start.duration(to: encoded))
                    stages["imageio_load_ms"] = ms(encoded.duration(to: decoded))
                    stages["save_ms"] = ms(decoded.duration(to: saved))
                    stages["delivery_ms"] = ms(start.duration(to: saved))
                } else {
                    let preview = try await renderer.render(url: url, maximumDimension: mode == "direct-native" || mode == "validate" ? nil : 3072)
                    image = preview.image
                    stages["delivery_ms"] = ms(start.duration(to: .now))
                    stages["native_width"] = preview.nativeSize.width
                    stages["native_height"] = preview.nativeSize.height
                }
                // Force ImageIO's possibly lazy JPEG pixels too. This is separate from delivery.
                let materialized = try autoreleasepool { try requireImage(context.createCGImage(CIImage(cgImage: image),
                    from: CGRect(x: 0, y: 0, width: image.width, height: image.height), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, deferred: false)) }
                stages["materialized_ms"] = ms(start.duration(to: .now))
                if mode == "validate-fit" {
                    let jpeg = try await SonyRawFormat.createFullSizeJPEG(from: url, quality: 1, useRAW9: true)
                    let legacy = try requireImage(OrientationNormalizedImageLoader.loadCGImage(from: jpeg))
                    guard max(image.width, image.height) <= 3072,
                          stages["native_width"] as? CGFloat == CGFloat(legacy.width),
                          stages["native_height"] as? CGFloat == CGFloat(legacy.height)
                    else { throw BenchmarkError.geometryChanged }
                    // Reuse one filter through several sizes, then native, then fit again.
                    // CIRAWFilter.nativeSize itself changes with scaleFactor on these files.
                    for dimension in [2048, 3840, 3072] {
                        let resized = try await renderer.render(url: url, maximumDimension: dimension)
                        guard max(resized.image.width, resized.image.height) <= dimension,
                              max(resized.image.width, resized.image.height) >= dimension - 2,
                              resized.nativeSize == CGSize(width: legacy.width, height: legacy.height)
                        else { throw BenchmarkError.geometryChanged }
                    }
                    let restored = try await renderer.render(url: url)
                    guard restored.image.width == legacy.width, restored.image.height == legacy.height,
                          restored.nativeSize == CGSize(width: legacy.width, height: legacy.height)
                    else { throw BenchmarkError.geometryChanged }
                    let fittedAgain = try await renderer.render(url: url, maximumDimension: 3072)
                    guard fittedAgain.nativeSize == restored.nativeSize,
                          max(fittedAgain.image.width, fittedAgain.image.height) <= 3072
                    else { throw BenchmarkError.geometryChanged }
                    stages["successive_fit_native_sizes_passed"] = true
                    let error = pixelDifference(legacy, image, context: context)
                    stages["fit_reference_mean_absolute_rgb_error"] = error
                    guard error < 3 else { throw BenchmarkError.colorChanged(error) }
                    if url == files.first {
                        try context.writePNGRepresentation(of: CIImage(cgImage: image),
                            to: scratch.appendingPathComponent("direct-fit.png"), format: .RGBA8,
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                    }
                }
                if mode == "validate" {
                    let jpeg = try await SonyRawFormat.createFullSizeJPEG(from: url, quality: 1, useRAW9: true)
                    let legacy = try requireImage(OrientationNormalizedImageLoader.loadCGImage(from: jpeg))
                    guard legacy.width == image.width, legacy.height == image.height else { throw BenchmarkError.geometryChanged }
                    let difference = pixelDifference(legacy, image, context: context)
                    stages["jpeg_reference_mean_absolute_rgb_error"] = difference
                    guard difference < 3 else { throw BenchmarkError.colorChanged(difference) }
                    let inspectionRenderer = RAWPreviewRenderer()
                    for exposure in (url == files.first ? [0.0, -1.0, 1.0] : []) {
                        let actual = try await inspectionRenderer.render(url: url, inspectionExposureEV: exposure).image
                        let expected = try legacyInspection(url: url, exposure: exposure, context: context)
                        let error = pixelDifference(expected, actual, context: context)
                        stages["inspection_\(exposure)_mean_absolute_rgb_error"] = error
                        // Inspection stays native resolution and retains the previous tone/recovery settings.
                        guard error < 0.1 else { throw BenchmarkError.colorChanged(error) }
                    }
                    // Returning from inspection must restore the unadjusted defaults.
                    let normal: CGImage
                    if url == files.first {
                        normal = try await inspectionRenderer.render(url: url).image
                        guard pixelDifference(normal, image, context: context) < 0.1 else { throw BenchmarkError.inspectionLeaked }
                    } else {
                        normal = image
                    }
                    if pass == 0, url == files.first {
                        let output = scratch.appendingPathComponent("direct-native.png")
                        try context.writePNGRepresentation(of: CIImage(cgImage: normal), to: output,
                            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
                        try jpeg.write(to: scratch.appendingPathComponent("legacy-native.jpg"))
                    }
                }
                var usage = rusage()
                getrusage(RUSAGE_SELF, &usage)
                stages.merge(["file": url.lastPathComponent, "mode": mode, "pass": pass,
                    "width": materialized.width, "height": materialized.height,
                    "raw9": true, "process_peak_rss_bytes": usage.ru_maxrss]) { _, new in new }
                let row = try JSONSerialization.data(withJSONObject: stages, options: [.sortedKeys])
                FileHandle.standardOutput.write(row + Data([10]))
            }
        }
    }

    static func ms(_ d: Duration) -> Double {
        Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15
    }
    // Keep failure handling explicit without depending on a test runner.
    static func requireImage(_ image: CGImage?) throws -> CGImage {
        guard let image else { throw BenchmarkError.noImage }
        return image
    }
    static func legacyInspection(url: URL, exposure: Double, context: CIContext) throws -> CGImage {
        try autoreleasepool {
            guard let raw = CIRAWFilter(imageURL: url) else { throw BenchmarkError.noImage }
            raw.decoderVersion = .version9
            raw.exposure = Float(exposure)
            raw.boostShadowAmount = 2
            if #available(macOS 26.0, *), raw.isHighlightRecoverySupported { raw.isHighlightRecoveryEnabled = true }
            guard let developed = raw.outputImage else { throw BenchmarkError.noImage }
            let inspected = developed.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 0.25, "inputShadowAmount": 0.0
            ])
            return try requireImage(context.createCGImage(inspected, from: inspected.extent, format: .RGBA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, deferred: false))
        }
    }
    static func pixelDifference(_ a: CGImage, _ b: CGImage, context: CIContext) -> Double {
        func pixels(_ image: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: 256 * 256 * 4)
            let output = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 256 / CGFloat(image.width), y: 256 / CGFloat(image.height)))
            bytes.withUnsafeMutableBytes {
                context.render(output, toBitmap: $0.baseAddress!, rowBytes: 256 * 4,
                    bounds: CGRect(x: 0, y: 0, width: 256, height: 256), format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            }
            return bytes
        }
        let lhs = pixels(a), rhs = pixels(b)
        var total = 0
        for index in lhs.indices where index % 4 != 3 { total += abs(Int(lhs[index]) - Int(rhs[index])) }
        return Double(total) / Double(256 * 256 * 3)
    }
    enum BenchmarkError: Error {
        case unsupportedRAW9(String), noImage, geometryChanged, colorChanged(Double), inspectionLeaked
    }
}
