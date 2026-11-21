import CoreGraphics
import Foundation
import PhotoEvidenceContracts
import PhotoEvidenceUI
@testable import RawCull
import Testing

@Suite("AF point orientation", .tags(.smoke))
struct AFPointOrientationTests {
    /// Expected upright position of sensor point (0.2, 0.3) for EXIF orientations 1–8.
    private static let expected = [
        CGPoint(x: 0.2, y: 0.3), CGPoint(x: 0.8, y: 0.3),
        CGPoint(x: 0.8, y: 0.7), CGPoint(x: 0.2, y: 0.7),
        CGPoint(x: 0.3, y: 0.2), CGPoint(x: 0.7, y: 0.2),
        CGPoint(x: 0.7, y: 0.8), CGPoint(x: 0.3, y: 0.8)
    ]

    @Test(arguments: Array(UInt32(1) ... UInt32(8)))
    func `sensor AF points map into the upright image`(orientation: UInt32) {
        let mapped = AFPointOrientation.oriented(CGPoint(x: 0.2, y: 0.3), orientation: orientation)
        let expected = Self.expected[Int(orientation) - 1]
        #expect(abs(mapped.x - expected.x) < 1e-9)
        #expect(abs(mapped.y - expected.y) < 1e-9)
        #expect(AFPointOrientation.transposes(orientation) == (5 ... 8).contains(orientation))
    }

    @Test func `unknown orientations leave the point unchanged`() {
        let point = CGPoint(x: 0.2, y: 0.3)
        #expect(AFPointOrientation.oriented(point, orientation: 0) == point)
        #expect(AFPointOrientation.oriented(point, orientation: 9) == point)
    }

    @Test(arguments: Array(UInt32(1) ... UInt32(8)))
    func `Burst Close-ups places an already oriented point without rotating it again`(orientation: UInt32) throws {
        let frame = CloseUpFrame(id: URL(filePath: "/fixture/a.arw"), name: "a", revision: "1")
        let oriented = AFPointOrientation.oriented(CGPoint(x: 0.2, y: 0.3), orientation: orientation)
        let fromOriented = try #require(BurstCloseUpAFPoint.availability(frame: frame, orientedPoint: oriented).target(for: frame))
        let fromSensor = try #require(BurstCloseUpAFPoint.availability(
            frame: frame, point: CGPoint(x: 0.2, y: 0.3), orientation: orientation,
        ).target(for: frame))
        #expect(fromOriented.center == fromSensor.center)
    }
}
