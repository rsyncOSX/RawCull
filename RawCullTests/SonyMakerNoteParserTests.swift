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
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

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

private func makeSyntheticTIFFWithEmptyIFD0(extension ext: String = "arw") throws -> URL {
    var bytes: [UInt8] = []
    bytes += [0x49, 0x49, 0x2A, 0x00]
    bytes += [0x08, 0x00, 0x00, 0x00]
    bytes += [0x00, 0x00] // IFD0 entry count = 0
    bytes += [0x00, 0x00, 0x00, 0x00] // next IFD = 0

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".\(ext)")
    try Data(bytes).write(to: url)
    return url
}

/// Writes a synthetic TIFF-like ARW with Sony-style embedded JPEG pointers:
/// IFD0 preview via StripOffsets/StripByteCounts, IFD1 thumbnail via
/// JPEGInterchangeFormat/JPEGInterchangeFormatLength, and IFD2 full JPEG via
/// StripOffsets/StripByteCounts.
private func makeSyntheticARWWithEmbeddedJPEGs() throws -> (url: URL, thumbnail: [UInt8], preview: [UInt8], full: [UInt8]) {
    let thumbnail: [UInt8] = [0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]
    let preview: [UInt8] = [0xFF, 0xD8, 0x10, 0x20, 0x30, 0xFF, 0xD9]
    let full: [UInt8] = [0xFF, 0xD8, 0xAA, 0xBB, 0xCC, 0xDD, 0xFF, 0xD9]

    let ifd0Offset = 0x08
    let ifd0EntryCount = 2
    let ifd0Size = 2 + ifd0EntryCount * 12 + 4
    let ifd1Offset = ifd0Offset + ifd0Size
    let ifd1EntryCount = 2
    let ifd1Size = 2 + ifd1EntryCount * 12 + 4
    let ifd2Offset = ifd1Offset + ifd1Size
    let ifd2EntryCount = 2
    let ifd2Size = 2 + ifd2EntryCount * 12 + 4
    let previewOffset = ifd2Offset + ifd2Size
    let thumbnailOffset = previewOffset + preview.count
    let fullOffset = thumbnailOffset + thumbnail.count

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
    bytes += le32(UInt32(ifd0Offset))

    bytes += le16(UInt16(ifd0EntryCount))
    bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: UInt32(previewOffset))
    bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: UInt32(preview.count))
    bytes += le32(UInt32(ifd1Offset))

    bytes += le16(UInt16(ifd1EntryCount))
    bytes += ifdEntry(tag: 0x0201, type: 4, count: 1, value: UInt32(thumbnailOffset))
    bytes += ifdEntry(tag: 0x0202, type: 4, count: 1, value: UInt32(thumbnail.count))
    bytes += le32(UInt32(ifd2Offset))

    bytes += le16(UInt16(ifd2EntryCount))
    bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: UInt32(fullOffset))
    bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: UInt32(full.count))
    bytes += le32(0)

    precondition(bytes.count == previewOffset)
    bytes += preview
    precondition(bytes.count == thumbnailOffset)
    bytes += thumbnail
    precondition(bytes.count == fullOffset)
    bytes += full

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".arw")
    try Data(bytes).write(to: url)
    return (url, thumbnail, preview, full)
}

/// Writes a synthetic A7R VI-style TIFF-like ARW using the offsets from the
/// ExifTool scan shape:
/// IFD0 PreviewImageStart/Length, IFD1 ThumbnailOffset/Length, and IFD2
/// JpgFromRawStart/Length. The tag ids underneath those ExifTool names are
/// the standard TIFF/JPEG pointer pairs RawCull parses.
private func makeSyntheticA7RVIARWWithEmbeddedJPEGs() throws -> (url: URL, thumbnail: [UInt8], preview: [UInt8], full: [UInt8]) {
    let thumbnail = try makeSyntheticJPEGData(width: 16, height: 12, red: 0.1, green: 0.2, blue: 0.8)
    let preview = try makeSyntheticJPEGData(width: 48, height: 32, red: 0.8, green: 0.1, blue: 0.2)
    let full = try makeSyntheticJPEGData(width: 96, height: 64, red: 0.2, green: 0.8, blue: 0.1)

    let ifd0Offset = 0x08
    let ifd0EntryCount = 3
    let ifd0Size = 2 + ifd0EntryCount * 12 + 4
    let ifd1Offset = ifd0Offset + ifd0Size
    let ifd1EntryCount = 2
    let ifd1Size = 2 + ifd1EntryCount * 12 + 4
    let rawSubIFDOffset = ifd1Offset + ifd1Size
    let rawSubIFDEntryCount = 2
    let rawSubIFDSize = 2 + rawSubIFDEntryCount * 12 + 4
    let ifd2Offset = rawSubIFDOffset + rawSubIFDSize
    let ifd2EntryCount = 2
    let ifd2Size = 2 + ifd2EntryCount * 12 + 4
    let subIFDArrayOffset = ifd2Offset + ifd2Size
    let thumbnailOffset = 44062
    let previewOffset = 204_962
    let fullOffset = 499_712

    func le16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8)]
    }
    func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
    func ifdEntry(tag: UInt16, type: UInt16, count: UInt32, value: UInt32) -> [UInt8] {
        le16(tag) + le16(type) + le32(count) + le32(value)
    }
    func pad(_ bytes: inout [UInt8], to offset: Int) {
        precondition(bytes.count <= offset)
        bytes += Array(repeating: 0, count: offset - bytes.count)
    }

    var bytes: [UInt8] = []
    bytes += [0x49, 0x49, 0x2A, 0x00]
    bytes += le32(UInt32(ifd0Offset))

    bytes += le16(UInt16(ifd0EntryCount))
    bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: UInt32(previewOffset))
    bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: UInt32(preview.count))
    bytes += ifdEntry(tag: 0x014A, type: 4, count: 2, value: UInt32(subIFDArrayOffset))
    bytes += le32(UInt32(ifd1Offset))

    bytes += le16(UInt16(ifd1EntryCount))
    bytes += ifdEntry(tag: 0x0201, type: 4, count: 1, value: UInt32(thumbnailOffset))
    bytes += ifdEntry(tag: 0x0202, type: 4, count: 1, value: UInt32(thumbnail.count))
    bytes += le32(0)

    // Raw SubIFD: contains raw strip pointers, not an embedded JPEG. The parser
    // must ignore this and continue to the JPEG SubIFD in the SubIFD array.
    bytes += le16(UInt16(rawSubIFDEntryCount))
    bytes += ifdEntry(tag: 0x0111, type: 4, count: 1, value: 4_796_416)
    bytes += ifdEntry(tag: 0x0117, type: 4, count: 1, value: 75_583_328)
    bytes += le32(0)

    bytes += le16(UInt16(ifd2EntryCount))
    bytes += ifdEntry(tag: 0x0201, type: 4, count: 1, value: UInt32(fullOffset))
    bytes += ifdEntry(tag: 0x0202, type: 4, count: 1, value: UInt32(full.count))
    bytes += le32(0)

    bytes += le32(UInt32(rawSubIFDOffset))
    bytes += le32(UInt32(ifd2Offset))

    pad(&bytes, to: thumbnailOffset)
    bytes += thumbnail
    pad(&bytes, to: previewOffset)
    bytes += preview
    pad(&bytes, to: fullOffset)
    bytes += full

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".arw")
    try Data(bytes).write(to: url)
    return (url, thumbnail, preview, full)
}

private func makeSyntheticJPEGData(
    width: Int,
    height: Int,
    red: CGFloat,
    green: CGFloat,
    blue: CGFloat,
) throws -> [UInt8] {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())

    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil,
    ))
    CGImageDestinationAddImage(destination, image, nil)
    try #require(CGImageDestinationFinalize(destination))
    return [UInt8](data as Data)
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
    func `Focus diagnostics report invalid TIFF header`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".arw")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data([0x00, 0x00, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00]).write(to: url)

        let diagnostics = SonyMakerNoteParser.focusLocationDiagnostics(from: url)

        #expect(diagnostics.value == nil)
        #expect(diagnostics.trace.contains { $0.contains("invalid TIFF header") })
    }

    @Test
    func `Focus diagnostics report missing ExifIFD stage`() throws {
        let url = try makeSyntheticTIFFWithEmptyIFD0()
        defer { try? FileManager.default.removeItem(at: url) }

        let diagnostics = SonyMakerNoteParser.focusLocationDiagnostics(from: url)

        #expect(diagnostics.value == nil)
        #expect(diagnostics.trace.contains { $0.contains("missing ExifIFD tag 0x8769") })
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

@MainActor
struct SonyEmbeddedJPEGLocatorTests {
    @Test
    func `Finds thumbnail preview and full JPEG locations through IFD chain`() throws {
        let fixture = try makeSyntheticARWWithEmbeddedJPEGs()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let locations = SonyMakerNoteParser.embeddedJPEGLocations(from: fixture.url)

        #expect(locations?.thumbnail?.length == fixture.thumbnail.count)
        #expect(locations?.preview?.length == fixture.preview.count)
        #expect(locations?.fullJPEG?.length == fixture.full.count)
    }

    @Test
    func `readEmbeddedJPEGData round-trips preview bytes`() throws {
        let fixture = try makeSyntheticARWWithEmbeddedJPEGs()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let location = try #require(SonyMakerNoteParser.embeddedJPEGLocations(from: fixture.url)?.preview)
        let data = SonyMakerNoteParser.readEmbeddedJPEGData(at: location, from: fixture.url)

        #expect(data == Data(fixture.preview))
    }

    @Test
    func `Finds A7R VI preview thumbnail and JPG from raw locations`() throws {
        let fixture = try makeSyntheticA7RVIARWWithEmbeddedJPEGs()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let locations = try #require(SonyMakerNoteParser.embeddedJPEGLocations(from: fixture.url))

        #expect(locations.thumbnail?.offset == 44062)
        #expect(locations.thumbnail?.length == fixture.thumbnail.count)
        #expect(locations.preview?.offset == 204_962)
        #expect(locations.preview?.length == fixture.preview.count)
        #expect(locations.fullJPEG?.offset == 499_712)
        #expect(locations.fullJPEG?.length == fixture.full.count)
    }

    @Test
    func `Sony thumbnail extraction decodes A7R VI embedded preview before raw ImageIO`() async throws {
        let fixture = try makeSyntheticA7RVIARWWithEmbeddedJPEGs()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let thumbnail = try await SonyThumbnailExtractor.extractSonyThumbnail(
            from: fixture.url,
            maxDimension: 64,
        )

        #expect(thumbnail.width == 48)
        #expect(thumbnail.height == 32)
    }

    @Test
    func `Sony JPG extraction decodes A7R VI JPG from raw before raw ImageIO`() async throws {
        let fixture = try makeSyntheticA7RVIARWWithEmbeddedJPEGs()
        defer { try? FileManager.default.removeItem(at: fixture.url) }

        let extracted = try #require(await JPGSonyARWExtractor.jpgSonyARWExtractor(
            from: fixture.url,
            fullSize: false,
        ))

        #expect(extracted.width == 96)
        #expect(extracted.height == 64)
    }

    @Test
    func `Returns nil locations for non TIFF data`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".arw")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]).write(to: url)

        #expect(SonyMakerNoteParser.embeddedJPEGLocations(from: url) == nil)
    }

    @Test
    func `Embedded JPEG diagnostics report checked IFD stages when no offsets exist`() throws {
        let url = try makeSyntheticARW()
        defer { try? FileManager.default.removeItem(at: url) }

        let diagnostics = SonyMakerNoteParser.embeddedJPEGLocationsDiagnostics(from: url)

        #expect(diagnostics.trace.contains { $0.contains("IFD0 preview JPEG tags not found") })
        #expect(diagnostics.trace.contains { $0.contains("no JPEG offsets found") })
        #expect(diagnostics.failure != nil)
    }
}
