//
//  SonyMakerNoteParserTests.swift
//  RawCullTests
//
//  Tests for SonyMakerNoteParser / TIFFParser using synthetic binary blobs.
//  TIFFParser is private, so all tests drive through SonyMakerNoteParser.focusLocation(from:).
//
//  Binary layout used by helpers below (little-endian TIFF):
//    0x0000  TIFF header  (8 bytes)
//    0x0008  IFD0         (2 + 1×12 + 4 = 18 bytes)  → ExifIFD at 0x001A
//    0x001A  ExifIFD      (2 + 1×12 + 4 = 18 bytes)  → MakerNote at configurable offset
//    <opt>   SONY DSC header (12 bytes, if present)
//    <mn>    Sony IFD     (2 + 1×12 + 4 = 18 bytes)
//    <fl>    FocusLocation (8 bytes = 4 × uint16)
//

import Foundation
@testable import RawCull
import Testing

// MARK: - Binary builder

/// Writes a synthetic TIFF ARW to a temp file and returns its URL.
/// - Parameters:
///   - focusTag:     0x2027 or 0x204a
///   - sonyHeader:   whether to prepend the 12-byte "SONY DSC " header before the Sony IFD
///   - width/height/x/y: FocusLocation values (uint16)
private func makeSyntheticARW(
    focusTag: UInt16 = 0x2027,
    sonyHeader: Bool = false,
    width: UInt16 = 9504,
    height: UInt16 = 6336,
    x: UInt16 = 4752,
    y: UInt16 = 3168,
) throws -> URL {
    // ── offset map ────────────────────────────────────────────────
    // IFD0        starts at 8   (size 18 → next region at 26)
    // ExifIFD     starts at 26  (size 18 → next region at 44)
    // MakerNote   starts at 44
    //   optional SONY DSC header: 12 bytes  (44…55)
    // Sony IFD    starts at 44 + (sonyHeader ? 12 : 0)
    //   Sony IFD size: 18 bytes
    // FocusLocation starts at SonyIFD + 18

    let makerNoteOffset = 44
    let sonyIFDOffset: Int = makerNoteOffset + (sonyHeader ? 12 : 0)
    let flOffset: Int = sonyIFDOffset + 18 // 2 + 1×12 + 4
    let totalSize: Int = flOffset + 8
    let makerNoteSize: Int = totalSize - makerNoteOffset

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

    // TIFF header
    bytes += [0x49, 0x49] // "II" little-endian
    bytes += [0x2A, 0x00] // magic 42
    bytes += le32(8) // IFD0 at offset 8

    // IFD0 (one entry: ExifIFD tag 0x8769)
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x8769, type: 4 /* LONG */, count: 1, value: 26)
    bytes += le32(0) // next IFD

    // ExifIFD (one entry: MakerNote tag 0x927C)
    bytes += le16(1)
    bytes += ifdEntry(tag: 0x927C, type: 7 /* UNDEFINED */,
                      count: UInt32(makerNoteSize),
                      value: UInt32(makerNoteOffset))
    bytes += le32(0)

    // Optional "SONY DSC " header (12 bytes: 9 ASCII + 3 null)
    if sonyHeader {
        bytes += [0x53, 0x4F, 0x4E, 0x59, // S O N Y
                  0x20, 0x44, 0x53, 0x43, //   D S C
                  0x20, 0x00, 0x00, 0x00] //   \0\0\0
    }

    // Sony IFD (one entry: FocusLocation)
    bytes += le16(1)
    bytes += ifdEntry(tag: focusTag, type: 3 /* SHORT */, count: 4,
                      value: UInt32(flOffset))
    bytes += le32(0)

    // FocusLocation data: width height x y  (each uint16 LE)
    bytes += le16(width) + le16(height) + le16(x) + le16(y)

    precondition(bytes.count == totalSize)

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".arw")
    try Data(bytes).write(to: url)
    return url
}

// MARK: - Tests

struct SonyMakerNoteParserTests {
    // MARK: Positive paths

    @Test
    func `Parses FocusLocation tag 0x2027 without SONY DSC header`() throws {
        let url = try makeSyntheticARW(focusTag: 0x2027)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = SonyMakerNoteParser.focusLocation(from: url)

        #expect(result == "9504 6336 4752 3168")
    }

    @Test
    func `Parses FocusLocation with SONY DSC header, skipping 12-byte prefix`() throws {
        let url = try makeSyntheticARW(focusTag: 0x2027, sonyHeader: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = SonyMakerNoteParser.focusLocation(from: url)

        #expect(result == "9504 6336 4752 3168")
    }

    @Test
    func `Falls back to tag 0x204a when 0x2027 is absent`() throws {
        let url = try makeSyntheticARW(focusTag: 0x204A)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = SonyMakerNoteParser.focusLocation(from: url)

        #expect(result == "9504 6336 4752 3168")
    }

    @Test
    func `Parses extreme sensor coordinates without overflow`() throws {
        // UInt16 max = 65535; verify Int conversion stays positive
        let url = try makeSyntheticARW(width: 65535, height: 65535, x: 65535, y: 65535)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = SonyMakerNoteParser.focusLocation(from: url)

        #expect(result == "65535 65535 65535 65535")
    }

    // MARK: Rejection paths

    @Test
    func `Returns nil for non-existent file`() {
        let url = URL(fileURLWithPath: "/nonexistent/fake.arw")
        #expect(SonyMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil for data shorter than TIFF header`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".arw")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data([0x49, 0x49, 0x2A, 0x00]).write(to: url) // only 4 bytes

        #expect(SonyMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil for unknown TIFF endian marker`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".arw")
        defer { try? FileManager.default.removeItem(at: url) }

        // First two bytes are not II or MM
        try Data([0x00, 0x00, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]).write(to: url)

        #expect(SonyMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil when focus coordinates are all zero`() throws {
        // x=0, y=0 is rejected as unset
        let url = try makeSyntheticARW(x: 0, y: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SonyMakerNoteParser.focusLocation(from: url) == nil)
    }

    @Test
    func `Returns nil when sensor dimensions are zero`() throws {
        let url = try makeSyntheticARW(width: 0, height: 0)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(SonyMakerNoteParser.focusLocation(from: url) == nil)
    }
}
