#if DEBUG
    import CoreGraphics
    import CryptoKit
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers

    struct InputFixture {
        let name: String
        let width: Int
        let height: Int
        let orientation: Int

        static let cases: [Self] = [
            .init(name: "landscape", width: 900, height: 600, orientation: 1),
            .init(name: "portrait", width: 600, height: 900, orientation: 1),
            .init(name: "square", width: 600, height: 600, orientation: 1),
            .init(name: "extreme", width: 1800, height: 180, orientation: 1)
        ] + (2 ... 8).map { .init(name: "orientation-\($0)", width: 900, height: 600, orientation: $0) }

        static let colors: [[UInt8]] = [[255, 0, 0], [0, 255, 0], [0, 0, 255], [255, 255, 0]]

        func decodedImage() throws -> CGImage {
            var pixels = [UInt8](repeating: 255, count: width * height * 4)
            let radius = Double(min(width, height)) * 0.22
            for y in 0 ..< height {
                for x in 0 ..< width {
                    let dx = Double(x) - Double(width) / 2
                    let dy = Double(y) - Double(height) / 2
                    var color: [UInt8] = (x % 50 < 2 || y % 50 < 2) ? [90, 90, 90] : [30, 30, 30]
                    if dx * dx + dy * dy <= radius * radius {
                        color = [0, 255, 255]
                    }
                    let left = x < width / 10, right = x >= width * 9 / 10
                    let top = y < height / 10, bottom = y >= height * 9 / 10
                    if left, top {
                        color = Self.colors[0]
                    }
                    if right, top {
                        color = Self.colors[1]
                    }
                    if left, bottom {
                        color = Self.colors[2]
                    }
                    if right, bottom {
                        color = Self.colors[3]
                    }
                    let offset = (y * width + x) * 4
                    for channel in 0 ..< 3 {
                        pixels[offset + channel] = color[channel]
                    }
                }
            }
            let image = try Self.image(pixels: pixels, width: width, height: height)
            // Exercise the same ImageIO orientation normalization as the app's
            // overview thumbnail loader, using lossless TIFF with explicit EXIF orientation.
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
            try #require(CGImageDestinationFinalize(destination))
            let source = try #require(CGImageSourceCreateWithData(data, nil))
            return try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
            ] as CFDictionary))
        }

        func assertStretchedMarkers(_ values: [Float], side: Int, mean: [Double], std: [Double]) throws {
            let order = [
                [0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]
            ][orientation - 1]
            let points = [(0.05, 0.05), (0.95, 0.05), (0.05, 0.95), (0.95, 0.95)]
            for (index, point) in points.enumerated() {
                let pixel = Int(point.1 * Double(side)) * side + Int(point.0 * Double(side))
                for channel in 0 ..< 3 {
                    let actual = Double(values[channel * side * side + pixel]) * std[channel] + mean[channel]
                    try #require(abs(actual - Double(Self.colors[order[index]][channel]) / 255) < 0.03)
                }
            }
            let bounds = try circleBounds(values, side: side, mean: mean, std: std)
            let rotated = orientation >= 5
            let decodedWidth = rotated ? height : width
            let decodedHeight = rotated ? width : height
            let diameter = Double(min(width, height)) * 0.44
            try #require(abs(Double(bounds.width) - diameter * Double(side) / Double(decodedWidth)) < 4)
            try #require(abs(Double(bounds.height) - diameter * Double(side) / Double(decodedHeight)) < 4)
        }

        func assertCenterCrop(_ values: [Float], side: Int, mean: [Double], std: [Double]) throws {
            let bounds = try circleBounds(values, side: side, mean: mean, std: std)
            try #require(abs(bounds.width - bounds.height) <= 3)
            try #require(abs(Double(bounds.width) - Double(side) * 0.44) < 4)
            if width == height {
                try assertStretchedMarkers(values, side: side, mean: mean, std: std)
            } else {
                // A shortest-edge center crop removes these entire corner markers.
                var retainedMarkers = 0
                for pixel in 0 ..< side * side {
                    let rgb = (0 ..< 3).map { Double(values[$0 * side * side + pixel]) * std[$0] + mean[$0] }
                    let isMarker = Self.colors.contains { color in
                        zip(rgb, color).allSatisfy { abs($0 - Double($1) / 255) < 0.02 }
                    }
                    if isMarker {
                        retainedMarkers += 1
                    }
                }
                try #require(retainedMarkers == 0)
            }
        }

        private func circleBounds(_ values: [Float], side: Int, mean: [Double], std: [Double]) throws -> (width: Int, height: Int) {
            var minX = side, minY = side, maxX = -1, maxY = -1
            for pixel in 0 ..< side * side {
                let r = Double(values[pixel]) * std[0] + mean[0]
                let g = Double(values[side * side + pixel]) * std[1] + mean[1]
                let b = Double(values[2 * side * side + pixel]) * std[2] + mean[2]
                if r < 0.2, g > 0.8, b > 0.8 {
                    minX = min(minX, pixel % side); maxX = max(maxX, pixel % side)
                    minY = min(minY, pixel / side); maxY = max(maxY, pixel / side)
                }
            }
            try #require(maxX >= minX && maxY >= minY)
            return (maxX - minX + 1, maxY - minY + 1)
        }

        func trace(image: CGImage, encoderWidth: Int, encoderHeight: Int, centerCrop: Bool) -> [String: Any] {
            var sampledWidth = encoderWidth, sampledHeight = encoderHeight
            if centerCrop {
                if image.width > image.height {
                    sampledWidth = Int(Double(encoderHeight) * Double(image.width) / Double(image.height))
                } else {
                    sampledHeight = Int(Double(encoderWidth) * Double(image.height) / Double(image.width))
                }
            }
            let cropX = max(0, (sampledWidth - encoderWidth) / 2)
            let cropY = max(0, (sampledHeight - encoderHeight) / 2)
            let scaleX = Double(sampledWidth) / Double(image.width)
            let scaleY = Double(sampledHeight) / Double(image.height)
            return [
                "fixture": name, "encodedSourceDimensions": [width, height], "exifOrientation": orientation,
                "normalizedSourceDimensions": [image.width, image.height],
                "appPreparedDimensions": [image.width, image.height],
                "sourceCropRectangle": [0, 0, image.width, image.height],
                "runtimeResizedDimensions": [sampledWidth, sampledHeight],
                "runtimeCropOrigin": [cropX, cropY], "encoderDimensions": [encoderWidth, encoderHeight],
                "retainedSourceRectangle": [Double(cropX) / scaleX, Double(cropY) / scaleY,
                                            Double(encoderWidth) / scaleX, Double(encoderHeight) / scaleY],
                "effectiveScale": [scaleX, scaleY], "padding": [0, 0],
                "coordinateOrigin": "top-left in orientation-normalized source",
                "geometryEvidence": "exact preprocessor tensor: corner identity and circle dimensions asserted"
            ]
        }

        static func detailRectangle(_ image: CGImage) -> CGRect {
            let side = min(image.width, image.height) / 2
            return CGRect(x: (image.width - side) / 2, y: (image.height - side) / 2,
                          width: side, height: side)
        }

        static func detailTrace(region: CGRect, image: CGImage, encoderSide: Int,
                                values: [Float], preview: String) -> [String: Any] {
            [
                "sourceRectangle": [region.minX, region.minY, region.width, region.height],
                "cropDimensions": [image.width, image.height],
                "encoderDimensions": [encoderSide, encoderSide],
                "effectiveScale": [Double(encoderSide) / Double(image.width), Double(encoderSide) / Double(image.height)],
                "padding": [0, 0], "preprocessedFloatSHA256": hash(values), "exactInputPreview": preview
            ]
        }

        static func rgba(_ image: CGImage) throws -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
            let context = try #require(CGContext(data: &bytes, width: image.width, height: image.height,
                                                 bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return bytes
        }

        static func image(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
            let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
            return try #require(CGImage(width: width, height: height, bitsPerComponent: 8,
                                        bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        }

        static func save(values: [Float], width: Int, height: Int, mean: [Double], std: [Double],
                         rescale: Double, to url: URL) throws {
            let count = width * height
            var bytes = [UInt8](repeating: 255, count: count * 4)
            for pixel in 0 ..< count {
                for channel in 0 ..< 3 {
                    let value = (Double(values[channel * count + pixel]) * std[channel] + mean[channel]) / rescale
                    bytes[pixel * 4 + channel] = UInt8(clamping: Int((value * 255).rounded()))
                }
            }
            try writePNG(image(pixels: bytes, width: width, height: height), to: url)
        }

        static func writePNG(_ image: CGImage, to url: URL) throws {
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            try #require(CGImageDestinationFinalize(destination))
        }

        static func json(_ value: some Encodable) throws -> Any {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
        }

        static func hash(_ values: [Float]) -> String {
            values.withUnsafeBytes { digest(Data($0)) }
        }

        static func halfHash(_ values: [Float]) -> String {
            values.map(Float16.init).withUnsafeBytes { digest(Data($0)) }
        }

        static func digest(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }

        static func bundleHash(_ root: URL) throws -> String {
            let enumerator = try #require(FileManager.default.enumerator(at: root,
                                                                         includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]))
            var files: [URL] = []
            for case let file as URL in enumerator {
                if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                    files.append(file)
                }
            }
            var tree = SHA256()
            for file in files.sorted(by: { $0.path < $1.path }) {
                let relative = String(file.path.dropFirst(root.path.count + 1))
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                var hash = SHA256()
                while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
                    hash.update(data: data)
                }
                let fileHash = hash.finalize().map { String(format: "%02x", $0) }.joined()
                tree.update(data: Data("\(relative)\0\(fileHash)\n".utf8))
            }
            return tree.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }
#endif
