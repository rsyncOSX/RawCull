import CoreGraphics
import Foundation
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

@MainActor
@Suite("Focus image downscaling")
struct FocusImageDownscalingTests {
    @Test
    func `JPEG scaling preserves existing pixels and dimensions`() async throws {
        let original = try makeImage(width: 2048, height: 1024)
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, nil)
        #expect(CGImageDestinationFinalize(destination))
        let imageSource = try #require(CGImageSourceCreateWithData(data, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(imageSource, 0, [kCGImageSourceShouldCache: false] as CFDictionary))

        let result = try #require(await image.downscaled(toWidth: 1024))
        let reference = try #require(CGContext(
            data: nil, width: 1024, height: 512,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        reference.interpolationQuality = .medium
        reference.draw(image, in: CGRect(x: 0, y: 0, width: 1024, height: 512))
        let expected = try #require(reference.makeImage())
        #expect(result.width == 1024)
        #expect(result.height == 512)
        #expect(result.bitsPerComponent == expected.bitsPerComponent)
        #expect(result.bitmapInfo == expected.bitmapInfo)
        let actualData = try #require(result.dataProvider?.data)
        let expectedData = try #require(expected.dataProvider?.data)
        #expect(actualData as Data == expectedData as Data)
    }

    @Test
    func `small images retain identity`() async throws {
        let image = try makeImage(width: 128, height: 64)
        let result = await image.downscaled(toWidth: 1024)
        #expect(result === image)
    }

    @Test
    func `cancelled scaling returns no image`() async throws {
        let image = try makeImage(width: 2048, height: 1024)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await image.downscaled(toWidth: 1024)
        }
        #expect(await task.value == nil)
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.1, green: 0.3, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        return try #require(context.makeImage())
    }
}
