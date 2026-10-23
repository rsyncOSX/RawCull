import AppKit

/// Builds a display-independent bitmap. Input images already have source orientation applied.
nonisolated enum GridThumbnailResizer {
    static func resize(_ image: NSImage, source: CGImage? = nil, maxPixelSize: Int = 200) -> NSImage? {
        guard maxPixelSize > 0,
              let source = source ?? image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let scale = min(Double(maxPixelSize) / Double(max(source.width, source.height)), 1)
        let width = max(1, Int((Double(source.width) * scale).rounded()))
        let height = max(1, Int((Double(source.height) * scale).rounded()))
        let colorSpace = source.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
            ?? CGColorSpace(name: CGColorSpace.sRGB)
        guard let colorSpace,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
              )
        else { return nil }
        context.interpolationQuality = .high
        context.setBlendMode(.copy)
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: CGSize(width: width, height: height))
    }
}
