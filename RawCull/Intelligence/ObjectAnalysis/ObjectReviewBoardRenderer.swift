import CoreGraphics
import CoreText
import Foundation

/// Renders one deterministic overview and numbered crop board for Qwen.
nonisolated enum ObjectReviewBoardRenderer {
    struct Board: Sendable {
        let image: CGImage
        let objectIDs: [String]
    }

    static func render(image: CGImage,
                       objects: [ObjectInstanceDeduplicator.Retained]) throws -> Board {
        let side = 2048
        guard let context = CGContext(data: nil, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else {
            throw ObjectAnalysisError.imageUnavailable
        }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let overview = CGRect(x: 0, y: 1024, width: side, height: 1024)
        drawAspectFit(image, in: overview, context: context)

        for (index, object) in objects.prefix(8).enumerated() {
            let column = index % 4
            let row = index / 4
            let panel = CGRect(x: column * 512, y: (1 - row) * 512,
                               width: 512, height: 512).insetBy(dx: 6, dy: 6)
            let header = CGRect(x: panel.minX, y: panel.maxY - 88,
                                width: panel.width, height: 88)
            let imagePanel = CGRect(x: panel.minX, y: panel.minY,
                                    width: panel.width, height: panel.height - header.height)
            let cropRect = crop(for: object.descriptor.normalizedBoundingBox,
                                width: image.width, height: image.height)
            guard let crop = image.cropping(to: cropRect),
                  let maskCrop = object.mask.cropping(to: cropRect) else { continue }
            context.saveGState()
            context.clip(to: imagePanel)
            drawAspectFit(crop, in: imagePanel, context: context)
            if let outline = outlineImage(maskCrop) {
                drawAspectFit(outline, in: imagePanel, context: context)
            }
            context.restoreGState()
            context.setFillColor(CGColor(gray: 0.05, alpha: 1))
            context.fill(header)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.setLineWidth(3)
            context.stroke(panel)
            drawNumber(object.descriptor.id, in: header, context: context)
        }
        guard let board = context.makeImage() else { throw ObjectAnalysisError.imageUnavailable }
        return Board(image: board, objectIDs: objects.map(\.descriptor.id))
    }

    static func crop(for box: CGRect, width: Int, height: Int) -> CGRect {
        let paddingX = max(8, box.width * CGFloat(width) * 0.15)
        let paddingY = max(8, box.height * CGFloat(height) * 0.15)
        let x0 = max(0, box.minX * CGFloat(width) - paddingX)
        let x1 = min(CGFloat(width), box.maxX * CGFloat(width) + paddingX)
        // Segment boxes use bottom-left coordinates on macOS; CGImage crops use top-left pixels.
        let y0 = max(0, (1 - box.maxY) * CGFloat(height) - paddingY)
        let y1 = min(CGFloat(height), (1 - box.minY) * CGFloat(height) + paddingY)
        return CGRect(x: floor(x0), y: floor(y0), width: max(1, ceil(x1) - floor(x0)),
                      height: max(1, ceil(y1) - floor(y0)))
    }

    private static func drawAspectFit(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let scale = min(rect.width / CGFloat(image.width), rect.height / CGFloat(image.height))
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        context.draw(image, in: CGRect(x: rect.midX - size.width / 2,
                                       y: rect.midY - size.height / 2,
                                       width: size.width, height: size.height))
    }

    private static func drawNumber(_ text: String, in rect: CGRect, context: CGContext) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 64, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor.white
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = CGPoint(x: rect.minX + 26, y: rect.minY + 10)
        CTLineDraw(line, context)
    }

    private static func outlineImage(_ mask: CGImage) -> CGImage? {
        let scale = CGFloat(512) / CGFloat(max(mask.width, mask.height))
        let width = max(2, Int((CGFloat(mask.width) * scale).rounded()))
        let height = max(2, Int((CGFloat(mask.height) * scale).rounded()))
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let maskContext = CGContext(data: &pixels, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        maskContext.interpolationQuality = .none
        maskContext.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))
        var edges = [UInt8](repeating: 0, count: width * height * 4)
        for y in 1 ..< (height - 1) {
            for x in 1 ..< (width - 1) {
                let p = y * width + x
                guard pixels[p] > 127,
                      pixels[p - 1] <= 127 || pixels[p + 1] <= 127
                      || pixels[p - width] <= 127 || pixels[p + width] <= 127 else { continue }
                let offset = p * 4
                edges[offset] = 255
                edges[offset + 1] = 220
                edges[offset + 2] = 20
                edges[offset + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(edges) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }
}
