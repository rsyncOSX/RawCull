import CoreGraphics
import Foundation
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

@Suite("Registered foreground crops", .tags(.smoke))
struct ReviewMaskRegistrationTests {
    @Test(arguments: 1 ... 8)
    func `asymmetric edge foreground stays registered after EXIF normalization`(_ orientation: Int) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: url) }
        let encodedBounds = CGRect(x: 0, y: 60, width: 16, height: 20)
        let pixels = (0 ..< 120 * 80).map { index in
            encodedBounds.contains(CGPoint(x: Double(index % 120) + 0.5, y: Double(index / 120) + 0.5)) ? UInt8(255) : 0
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let original = try #require(CGImage(width: 120, height: 80, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 120,
                                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                          provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let source = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .appearance))
        let context = try #require(CGContext(data: nil, width: source.image.width, height: source.image.height, bitsPerComponent: 8,
                                            bytesPerRow: source.image.width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.draw(source.image, in: source.metadata.sourceSpace.bounds)
        let mask = try #require(context.makeImage())
        let registration = try ReviewMaskRegistration.make(mask: mask, source: source, producerBounds: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let expected = try source.metadata.orientationTransform.normalizedRect(fromEncoded: encodedBounds)
        #expect(registration.foregroundBounds == expected)
        #expect(registration.touchesSourceEdge)
        #expect(registration.warning != nil)
        let foreground = try SubjectMaskForeground.decode(mask, width: source.image.width, height: source.image.height)
        let region = try source.region(rect: expected, purpose: "registered foreground", encoder: .init(width: 448, height: 448, strategy: .stretch))
        #expect(region.edgeClipped)
        #expect(ReviewMaskRegistration.retainedFraction(foreground, in: region.sourceRect) == 1)
        #expect(ReviewMaskRegistration.retainedFraction(foreground, in: region.encoder.retainedSourceRect) == 1)
        #expect(try source.crop(region).width == Int(region.sourceRect.width))
        let technical = try await ReviewImageSourceService().load(.init(url: url, preference: .highQualityPreview, policy: .technical))
        #expect(try source.mapSourceRect(expected, to: technical) == expected)
    }

    @Test func `foreground retention separates avoidable truncation from source edge contact`() throws {
        let provider = try #require(CGDataProvider(data: Data(Array(repeating: UInt8(255), count: 120 * 40)) as CFData))
        let mask = try #require(CGImage(width: 120, height: 40, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: 120,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let foreground = try SubjectMaskForeground.decode(mask, width: 120, height: 40)
        let trace = try ReviewEncoderGeometry(width: 256, height: 256, strategy: .shortestSideCenterCrop).trace(crop: CGRect(x: 0, y: 0, width: 120, height: 40))
        #expect(ReviewMaskRegistration.retainedFraction(foreground, in: trace.retainedSourceRect) < 0.35)
        #expect(ReviewMaskRegistration.retainedFraction(foreground, in: CGRect(x: 0.25, y: 0.25, width: 119.5, height: 39.5)) == 1)
        #expect(ReviewMaskRegistration.retainedFraction(foreground, in: CGRect(x: 10, y: 10, width: 20, height: 20)) < 0.1)
    }
}
