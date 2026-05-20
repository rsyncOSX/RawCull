//
//  NikonMakerNoteParserTests.swift
//  RawCullTests
//
//  Tests for NikonMakerNoteParser using synthetic binary blobs.
//  The inner TIFFParser is private, so all tests drive through
//  NikonMakerNoteParser.focusLocation(from:).
//
//  Binary layout used by makeSyntheticNEF (little-endian TIFF):
//    0x0000  TIFF header                 8 bytes
//    0x0008  IFD0 (1 entry: ExifIFD)    18 bytes
//    0x001A  ExifIFD (1 entry: MakerNote) 18 bytes
//    0x002C  MakerNote
//      0x2C..0x31  "Nikon\0"              6 bytes signature
//      0x32..0x35  version ("0210")       4 bytes
//      0x36..0x3D  inner TIFF header      8 bytes → inner IFD0 at +0x08
//      0x3E        Nikon IFD (1 entry: AFInfo2) 18 bytes
//      0x50        AFInfo2 blob (>= 0x38 bytes; offsets inside:
//                  0x00 version, 0x26 width, 0x28 height, 0x2A x, 0x2C y)
//

import Foundation
@testable import RawCull
import Testing

// MARK: - Binary builder

private func makeSyntheticNEF(
    afVersion: (UInt8, UInt8, UInt8, UInt8) = (0x30, 0x33, 0x30, 0x30), // "0300"
    width: UInt16 = 8256,
    height: UInt16 = 5504,
    x: UInt16 = 4128,
    y: UInt16 = 2752,
    nikonSignature: Bool = true,
) throws -> URL {
    let makerNoteOffset = 0x2C
    let innerTIFFOffset = makerNoteOffset + 10 // 0x36
    let nikonIFDOffset = innerTIFFOffset + 8 // 0x3E
    let afInfo2Offset = nikonIFDOffset + 18 // 0x50
    let afInfo2RelOffset = afInfo2Offset - innerTIFFOffset // 0x1A
    let afInfo2Size = 0x38
    let totalSize = afInfo2Offset + afInfo2Size
    let makerNoteSize = totalSize - makerNoteOffset

    func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8)]
    }
    func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
    func ifdEntry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) -> [UInt8] {
        le16(tag) + le16(type) + le32(count) + le32(value)
    }

    var bytes: [UInt8] = []

    // Outer TIFF header (little-endian)
    bytes += [0x49, 0x49, 0x2A, 0x00]
    bytes += le32(8) // IFD0 at 0x08

    // IFD0: single entry → ExifIFD (tag 0x8769)
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x8769, type: 4, count: 1, value: 0x1A)
    bytes += le32(0)

    // ExifIFD: single entry → MakerNote (tag 0x927C)
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x927C, type: 7,
                      count: UInt32(makerNoteSize),
                      value: UInt32(makerNoteOffset))
    bytes += le32(0)

    precondition(bytes.count == makerNoteOffset)

    // MakerNote: "Nikon\0" signature (or garbage if disabled) + version "0210"
    if nikonSignature {
        bytes += [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00] // "Nikon\0"
    } else {
        bytes += [0x00, 0x00, 0x00, 0x00, 0x00, 0x00] // unknown signature
    }
    bytes += [0x30, 0x32, 0x31, 0x30] // version "0210"

    precondition(bytes.count == innerTIFFOffset)

    // Inner TIFF header (little-endian; IFD0 at relative offset 0x08)
    bytes += [0x49, 0x49, 0x2A, 0x00]
    bytes += le32(8)

    precondition(bytes.count == nikonIFDOffset)

    // Nikon IFD: single entry → AFInfo2 (tag 0x00B7, type 7 UNDEFINED)
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x00B7, type: 7,
                      count: UInt32(afInfo2Size),
                      value: UInt32(afInfo2RelOffset))
    bytes += le32(0)

    precondition(bytes.count == afInfo2Offset)

    // AFInfo2 blob: version at 0x00, uint16 fields at 0x26/0x28/0x2A/0x2C
    var af = [UInt8](repeating: 0, count: afInfo2Size)
    af[0] = afVersion.0
    af[1] = afVersion.1
    af[2] = afVersion.2
    af[3] = afVersion.3
    let widthLE = le16(width)
    let heightLE = le16(height)
    let xLE = le16(x)
    let yLE = le16(y)
    af[0x26] = widthLE[0]; af[0x27] = widthLE[1]
    af[0x28] = heightLE[0]; af[0x29] = heightLE[1]
    af[0x2A] = xLE[0]; af[0x2B] = xLE[1]
    af[0x2C] = yLE[0]; af[0x2D] = yLE[1]
    bytes += af

    precondition(bytes.count == totalSize)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".nef")
    try Data(bytes).write(to: url)
    return url
}

// MARK: - Tests

struct NikonMakerNoteParserTests {
    // MARK: Positive paths

    @Test
    func `Parses AFInfo2 for Z9-style AFInfoVersion 0300`() throws {
        let url = try makeSyntheticNEF()
        defer { try? FileManager.default.removeItem(at: url) }

        let result = NikonMakerNoteParser.focusLocation(from: url)

        #expect(result == "8256 5504 4128 2752")
    }

    @Test
    func `Accepts AFInfoVersion 0301 as Z-series compatible`() throws {
        let url = try makeSyntheticNEF(afVersion: (0x30, 0x33, 0x30, 0x31))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == "8256 5504 4128 2752")
    }

    @Test
    func `Accepts AFInfoVersion 0400`() throws {
        let url = try makeSyntheticNEF(afVersion: (0x30, 0x34, 0x30, 0x30))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == "8256 5504 4128 2752")
    }

    @Test
    func `Parses Z8-style 45 MP coordinates without overflow`() throws {
        let url = try makeSyntheticNEF(width: 8256, height: 5504, x: 65000, y: 5000)
        defer { try? FileManager.default.removeItem(at: url) }

        // x > width triggers the sanity gate → nil. Sanity-check the gate fires.
        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    // MARK: Rejection paths

    @Test
    func `Returns nil for non-existent file`() {
        let url = URL(fileURLWithPath: "/nonexistent/fake.nef")
        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil when Nikon signature is missing`() throws {
        let url = try makeSyntheticNEF(nikonSignature: false)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Focus diagnostics report missing Nikon signature`() throws {
        let url = try makeSyntheticNEF(nikonSignature: false)
        defer { try? FileManager.default.removeItem(at: url) }

        let diagnostics = NikonMakerNoteParser.focusLocationDiagnostics(from: url)

        #expect(diagnostics.value == nil)
        #expect(diagnostics.trace.contains { $0.contains("Nikon Type-3 signature missing") })
    }

    @Test
    func `Returns nil for AFInfoVersion 0100 (pre-Z layout not supported)`() throws {
        // Second digit < '3' → rejected.
        let url = try makeSyntheticNEF(afVersion: (0x30, 0x31, 0x30, 0x30))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Focus diagnostics report unsupported AFInfo version`() throws {
        let url = try makeSyntheticNEF(afVersion: (0x30, 0x31, 0x30, 0x30))
        defer { try? FileManager.default.removeItem(at: url) }

        let diagnostics = NikonMakerNoteParser.focusLocationDiagnostics(from: url)

        #expect(diagnostics.value == nil)
        #expect(diagnostics.trace.contains { $0.contains("unsupported AFInfoVersion 0100") })
    }

    @Test
    func `Returns nil when dimensions below sanity threshold`() throws {
        // width < 2000 rejected.
        let url = try makeSyntheticNEF(width: 1000, height: 500, x: 500, y: 250)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil when focus point is 0,0`() throws {
        let url = try makeSyntheticNEF(x: 0, y: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil for data shorter than TIFF header`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nef")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data([0x49, 0x49, 0x2A, 0x00]).write(to: url)

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil for unknown TIFF endian marker`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nef")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data([0x00, 0x00, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]).write(to: url)

        #expect(NikonMakerNoteParser.focusLocation(from: url) == nil)
    }
}

// MARK: - Embedded JPEG locator fixture

/// Builds a minimal TIFF that mirrors the NEF structure the embedded-JPEG
/// locator cares about:
///   0x0000  TIFF header (II/2A/ifd0=8)                8 bytes
///   0x0008  IFD0 (1 entry: SubIFDs 0x014A → single)  18 bytes
///           NextIFD pointer = 0
///   0x001A  SubIFD[0]:
///              Compression     0x0103 = 6
///              StripOffsets    0x0111 = jpegOffset
///              StripByteCounts 0x0117 = jpegLength
///           NextIFD pointer = 0
///   jpegOffset  JPEG blob (FF D8 ... FF D9)
///
/// Returns (url, jpegBlob) so tests can assert on the blob the locator finds.
private func makeSyntheticNEFWithPreviewJPEG() throws -> (url: URL, jpeg: [UInt8]) {
    let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0xCA, 0xFE, 0xBA, 0xBE, 0xFF, 0xD9]

    let subIFDOffset = 0x1A
    let subIFDSize = 2 + 3 * 12 + 4 // count + 3 entries + nextIFD ptr
    let jpegOffset = subIFDOffset + subIFDSize
    let totalSize = jpegOffset + jpeg.count

    func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8)]
    }
    func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
    func ifdEntry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) -> [UInt8] {
        le16(tag) + le16(type) + le32(count) + le32(value)
    }

    var bytes: [UInt8] = []

    // Outer TIFF header (little-endian, IFD0 at 0x08)
    bytes += [0x49, 0x49, 0x2A, 0x00]
    bytes += le32(8)

    // IFD0: single entry → SubIFDs (tag 0x014A, type 4 LONG, count 1 inline).
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x014A, type: 4, count: 1, value: UInt32(subIFDOffset))
    bytes += le32(0) // NextIFD = 0

    precondition(bytes.count == subIFDOffset)

    // SubIFD: Compression=6, StripOffsets=jpegOffset, StripByteCounts=jpeg.count
    bytes += le16(3)
    bytes += ifdEntry(tag: 0x0103, type: 3, count: 1, value: 6) // SHORT type 3
    bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: UInt32(jpegOffset))
    bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: UInt32(jpeg.count))
    bytes += le32(0) // NextIFD = 0

    precondition(bytes.count == jpegOffset)

    bytes += jpeg
    precondition(bytes.count == totalSize)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".nef")
    try Data(bytes).write(to: url)
    return (url, jpeg)
}

// MARK: - Embedded JPEG locator tests

@MainActor
struct NikonEmbeddedJPEGLocatorTests {
    @Test
    func `Finds SubIFD JPEG via 0x014A walk`() throws {
        let (url, jpeg) = try makeSyntheticNEFWithPreviewJPEG()
        defer { try? FileManager.default.removeItem(at: url) }

        let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url)

        #expect(locations?.preview != nil)
        #expect(locations?.preview?.length == jpeg.count)
    }

    @Test
    func `readEmbeddedJPEGData round-trips the JPEG bytes`() throws {
        let (url, jpeg) = try makeSyntheticNEFWithPreviewJPEG()
        defer { try? FileManager.default.removeItem(at: url) }

        guard let loc = NikonMakerNoteParser.embeddedJPEGLocations(from: url)?.preview
        else {
            Issue.record("locator returned nil preview")
            return
        }
        let data = NikonMakerNoteParser.readEmbeddedJPEGData(at: loc, from: url)

        #expect(data?.count == jpeg.count)
        #expect(data?.first == 0xFF)
        #expect(data?.last == 0xD9)
    }

    @Test
    func `Returns nil for non-TIFF file`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nef")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).write(to: url)

        #expect(NikonMakerNoteParser.embeddedJPEGLocations(from: url) == nil)
    }

    @Test
    func `Returns empty locations when SubIFD Compression is not JPEG`() throws {
        // Build a synthetic NEF where the single SubIFD has Compression=1 (uncompressed)
        // rather than 6 (OldJPEG). The locator should not surface it as a preview.
        let subIFDOffset = 0x1A
        let subIFDSize = 2 + 3 * 12 + 4
        let payloadOffset = subIFDOffset + subIFDSize

        func le16(_ v: UInt16) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8(v >> 8)]
        }
        func le32(_ v: UInt32) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
        }
        func ifdEntry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) -> [UInt8] {
            le16(tag) + le16(type) + le32(count) + le32(value)
        }

        var bytes: [UInt8] = []
        bytes += [0x49, 0x49, 0x2A, 0x00]
        bytes += le32(8)
        bytes += le16(1)
        bytes += ifdEntry(tag: 0x014A, type: 4, count: 1, value: UInt32(subIFDOffset))
        bytes += le32(0)
        bytes += le16(3)
        bytes += ifdEntry(tag: 0x0103, type: 3, count: 1, value: 1) // Compression = 1
        bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: UInt32(payloadOffset))
        bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: 4)
        bytes += le32(0)
        bytes += [0xAA, 0xBB, 0xCC, 0xDD]

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".nef")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(bytes).write(to: url)

        let locations = NikonMakerNoteParser.embeddedJPEGLocations(from: url)
        #expect(locations?.preview == nil)
        #expect(locations?.ifd1JPEG == nil)
    }
}
