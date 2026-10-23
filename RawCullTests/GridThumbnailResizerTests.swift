import AppKit
@testable import RawCull
import Testing

struct GridThumbnailResizerTests {
    @Test(arguments: [
        (CGSize(width: 800, height: 400), CGSize(width: 200, height: 100)),
        (CGSize(width: 400, height: 800), CGSize(width: 100, height: 200)),
        (CGSize(width: 40, height: 20), CGSize(width: 40, height: 20)),
        (CGSize(width: 1, height: 1000), CGSize(width: 1, height: 200))
    ])
    func `grid pixel bounds are independent of logical image size`(dimensions: (CGSize, CGSize)) throws {
        let (size, expected) = dimensions
        let width = Int(size.width)
        let height = Int(size.height)
        let expectedWidth = Int(expected.width)
        let expectedHeight = Int(expected.height)
        let source = try makeImage(width: width, height: height)
        let image = NSImage(cgImage: source, size: CGSize(width: width * 2, height: height * 2))
        let scaled = try #require(GridThumbnailResizer.resize(image))
        let bitmap = try #require(scaled.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(bitmap.width == expectedWidth)
        #expect(bitmap.height == expectedHeight)
        #expect(scaled.size == CGSize(width: expectedWidth, height: expectedHeight))
    }

    @Test
    func `resizing preserves row orientation transparency and wide gamut color space`() throws {
        let source = try makeImage(width: 400, height: 200)
        let image = NSImage(cgImage: source, size: CGSize(width: 400, height: 200))
        let scaled = try #require(GridThumbnailResizer.resize(image, source: source))
        let bitmap = try #require(scaled.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(bitmap.colorSpace?.name == source.colorSpace?.name)
        let originalBottom = try pixel(source, column: 100, row: 25)
        let originalTop = try pixel(source, column: 100, row: 175)
        let scaledBottom = try pixel(bitmap, column: 50, row: 12)
        let scaledTop = try pixel(bitmap, column: 50, row: 87)
        for (before, after) in zip(originalBottom + originalTop, scaledBottom + scaledTop) {
            #expect(abs(Int(before) - Int(after)) <= 2)
        }
    }

    @Test
    func `invalid target size produces no thumbnail`() throws {
        let source = try makeImage(width: 10, height: 10)
        let image = NSImage(cgImage: source, size: CGSize(width: 10, height: 10))
        #expect(GridThumbnailResizer.resize(image, maxPixelSize: 0) == nil)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        context.fill(CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        return try #require(context.makeImage())
    }

    private func pixel(_ image: CGImage, column: Int, row: Int) throws -> [UInt8] {
        let cropped = try #require(image.cropping(to: CGRect(x: column, y: row, width: 1, height: 1)))
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return Array(UnsafeBufferPointer(start: data, count: 4))
    }
}
