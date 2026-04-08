//
//  SonyMakerNoteParser.swift
//  RawCull
//
//  Parses Sony ARW raw files to extract AF focus location natively,
//  without requiring exiftool. Supports ILCE-1, ILCE-1M2, ILCE-7M5, ILCE-7RM5,
//  and ILCE-9M3 (A9 III stores TIFF metadata near EOF; requires full-file read).
//
//  Technical background
//  ─────────────────────
//  Sony ARW is TIFF-based (little-endian). Focus location lives in:
//    TIFF IFD0 → ExifIFD (tag 0x8769) → MakerNote (tag 0x927C)
//      → Sony MakerNote IFD → FocusLocation (tag 0x2027)
//
//  Tag 0x2027 is int16u[4] = [imageWidth, imageHeight, focusX, focusY],
//  with origin at top-left. Values are already in full sensor pixel space;
//  no scaling is required.  (Tag 0x204a is a redundant copy, same values
//  within one pixel.)
//
//  NOTE: tag 0x9400 (AFInfo) is an enciphered binary block; its contents
//  are NOT used for focus location.
//
//  Sony MakerNote IFD entries use absolute file offsets (not relative to
//  the MakerNote start), consistent with ExifTool's ProcessExif behaviour.
//

import Foundation

// MARK: - Diagnostic types

/// Complete record of a verbose TIFF IFD walk through a Sony ARW file.
/// Used by the body-compatibility test to diagnose unsupported bodies and
/// identify candidate tags for extending `SonyMakerNoteParser`.
struct TIFFWalkDiagnostics: Sendable {
    let isLittleEndian: Bool
    let ifd0Offset: Int
    let ifd0EntryCount: Int
    let exifIFDOffset: Int?
    let exifEntryCount: Int?
    let makerNoteOffset: Int?
    let makerNoteSize: Int?
    let hasSonyPrefix: Bool
    let sonyIFDOffset: Int?
    let sonyIFDEntryCount: Int?
    /// Every tag number found in the Sony MakerNote IFD, sorted ascending.
    let sonyAllTags: [UInt16]
    /// 0x2027 or 0x204A if a focus location tag was found, nil otherwise.
    let focusTagUsed: UInt16?
    let focusOffset: Int?
    /// Raw 8 bytes of the FocusLocation value (4 × uint16 LE).
    let focusRawBytes: [UInt8]?
    /// Decoded result; nil when tag is missing or dimensions are zero.
    let focusResult: FocusLocationValues?

    struct FocusLocationValues: Sendable {
        let width: Int
        let height: Int
        let x: Int
        let y: Int
    }
}

// MARK: - Embedded JPEG locations

/// Absolute file offsets for the three JPEG images embedded in every Sony ARW.
/// Used as a fallback when the macOS RA16 decoder cannot handle the file
/// (e.g. ARW 6.0 from the A7V returns err=-50 from CGImageSourceCreateThumbnailAtIndex).
struct EmbeddedJPEGLocations: Sendable {
    struct Location: Sendable {
        let offset: Int
        let length: Int
    }
    /// IFD1 tiny thumbnail (~8 KB, ~160 px).
    let thumbnail: Location?
    /// IFD0 preview JPEG (~400 KB, 1616×1080).
    let preview: Location?
    /// IFD2 full-resolution JPEG (~4 MB, 7008×4672).
    let fullJPEG: Location?

    nonisolated init(thumbnail: Location? = nil, preview: Location? = nil, fullJPEG: Location? = nil) {
        self.thumbnail = thumbnail
        self.preview = preview
        self.fullJPEG = fullJPEG
    }
}

// MARK: - Parser

enum SonyMakerNoteParser {
    /// Returns "width height x y" for the AF focus location encoded in the Sony MakerNote.
    nonisolated static func focusLocation(from url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // Fast path: read only the first 4 MB. Most Sony bodies (A1, A1 II, A7 V,
        // A7R V) store MakerNote metadata well within this range.
        guard let data = try? fh.read(upToCount: 4 * 1024 * 1024) else { return nil }
        if let result = TIFFParser(data: data)?.parseSonyFocusLocation() {
            return "\(result.width) \(result.height) \(result.x) \(result.y)"
        }

        // Slow path: IFD0 may fall beyond the 4 MB window (e.g. ILCE-9M3 stores
        // TIFF metadata in the last 1–2 MB of the file). Re-read the full file.
        try? fh.seek(toOffset: 0)
        guard let full = try? fh.read(upToCount: Int.max),
              full.count > data.count,
              let result = TIFFParser(data: full)?.parseSonyFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
    }

    /// Parses the TIFF IFD chain and returns the absolute file offsets of the three
    /// embedded JPEGs present in all Sony ARW files. Only the first 64 KB of the file
    /// is read because all IFD structures fall within that range.
    nonisolated static func embeddedJPEGLocations(from url: URL) -> EmbeddedJPEGLocations? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 65536),
              let parser = TIFFParser(data: data)
        else { return nil }
        return parser.parseEmbeddedJPEGLocations()
    }

    /// Reads raw bytes for an embedded JPEG from the file at the given absolute offset.
    nonisolated static func readEmbeddedJPEGData(
        at location: EmbeddedJPEGLocations.Location,
        from url: URL
    ) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(location.offset))
        return try? fh.read(upToCount: location.length)
    }

    /// Performs a verbose TIFF IFD walk and returns diagnostic details for
    /// every level: IFD0 → ExifIFD → MakerNote → Sony IFD → FocusLocation.
    /// Returns `nil` only if the file cannot be opened or lacks a valid TIFF header.
    nonisolated static func tiffDiagnostics(from url: URL) -> TIFFWalkDiagnostics? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 4 * 1024 * 1024),
              let parser = TIFFParser(data: data)
        else { return nil }
        let result = parser.runDiagnostics()

        // If IFD0 reports 0 entries the offset likely falls outside the 4 MB window
        // (e.g. ILCE-9M3). Retry with the full file so all IFD levels are reachable.
        guard result.ifd0EntryCount == 0 else { return result }
        try? fh.seek(toOffset: 0)
        guard let full = try? fh.read(upToCount: Int.max),
              full.count > data.count,
              let fullParser = TIFFParser(data: full)
        else { return result }
        return fullParser.runDiagnostics()
    }
}

// MARK: - TIFF binary parser

private struct TIFFParser {
    let data: Data
    let le: Bool

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        if b0 == 0x49, b1 == 0x49 { le = true } else if b0 == 0x4D, b1 == 0x4D { le = false } else { return nil }
        self.data = data
    }

    nonisolated func parseSonyFocusLocation() -> (width: Int, height: Int, x: Int, y: Int)? {
        guard let ifd0 = readU32(at: 4).map(Int.init) else { return nil }

        // Navigate: IFD0 → ExifIFD → MakerNote IFD
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769),
              let (mnOffset, _) = tagDataRange(in: exifIFD, tag: 0x927C) else { return nil }

        let ifdStart = sonyIFDStart(at: mnOffset)

        // Tag 0x2027: FocusLocation — int16u[4] = [width, height, x, y] in pixel coords.
        // Try 0x2027 first, fall back to 0x204a (identical values within one pixel).
        let flTag: UInt16 = tagDataRange(in: ifdStart, tag: 0x2027) != nil ? 0x2027 : 0x204A
        guard let (flOffset, flSize) = tagDataRange(in: ifdStart, tag: flTag),
              flSize >= 8 else { return nil }

        let width = Int(readU16(at: flOffset + 0))
        let height = Int(readU16(at: flOffset + 2))
        let x = Int(readU16(at: flOffset + 4))
        let y = Int(readU16(at: flOffset + 6))

        guard width > 0, height > 0, x > 0 || y > 0 else { return nil }

        return (width, height, x, y)
    }

    // MARK: Diagnostics

    /// Verbose IFD walk used by the body-compatibility test.
    nonisolated func runDiagnostics() -> TIFFWalkDiagnostics {
        let empty = TIFFWalkDiagnostics(
            isLittleEndian: le, ifd0Offset: 0, ifd0EntryCount: 0,
            exifIFDOffset: nil, exifEntryCount: nil,
            makerNoteOffset: nil, makerNoteSize: nil,
            hasSonyPrefix: false, sonyIFDOffset: nil, sonyIFDEntryCount: nil,
            sonyAllTags: [], focusTagUsed: nil,
            focusOffset: nil, focusRawBytes: nil, focusResult: nil)

        guard let ifd0Raw = readU32(at: 4) else { return empty }
        let ifd0 = Int(ifd0Raw)
        let ifd0Count = Int(readU16(at: ifd0))

        // ExifIFD (tag 0x8769)
        var exifIFDOffset: Int?
        var exifEntryCount: Int?
        if let (valLoc, _) = tagDataRange(in: ifd0, tag: 0x8769),
           let off = readU32(at: valLoc).map(Int.init) {
            exifIFDOffset = off
            exifEntryCount = Int(readU16(at: off))
        }

        // MakerNote (tag 0x927C)
        var makerNoteOffset: Int?
        var makerNoteSize: Int?
        if let exifOff = exifIFDOffset,
           let (mnOff, mnSz) = tagDataRange(in: exifOff, tag: 0x927C) {
            makerNoteOffset = mnOff
            makerNoteSize = mnSz
        }

        // Sony IFD
        var hasSonyPrefix = false
        var sonyIFDOffset: Int?
        var sonyIFDEntryCount: Int?
        var sonyAllTags: [UInt16] = []
        var focusTagUsed: UInt16?
        var focusOffset: Int?
        var focusRawBytes: [UInt8]?
        var focusResult: TIFFWalkDiagnostics.FocusLocationValues?

        if let mnOff = makerNoteOffset {
            let ifdStart = sonyIFDStart(at: mnOff)
            hasSonyPrefix = ifdStart != mnOff
            sonyIFDOffset = ifdStart

            let entryCount = Int(readU16(at: ifdStart))
            sonyIFDEntryCount = entryCount

            // Collect all tag numbers, sorted ascending for readability
            for i in 0 ..< entryCount {
                let e = ifdStart + 2 + i * 12
                guard e + 12 <= data.count else { break }
                sonyAllTags.append(readU16(at: e))
            }
            sonyAllTags.sort()

            // Try 0x2027 first, fall back to 0x204A (mirrors parseSonyFocusLocation)
            for tag: UInt16 in [0x2027, 0x204A] {
                guard let (flOff, flSz) = tagDataRange(in: ifdStart, tag: tag), flSz >= 8 else { continue }
                focusTagUsed = tag
                focusOffset = flOff
                var raw = [UInt8]()
                for j in 0 ..< 8 where flOff + j < data.count {
                    raw.append(data[flOff + j])
                }
                focusRawBytes = raw
                let w = Int(readU16(at: flOff + 0))
                let h = Int(readU16(at: flOff + 2))
                let x = Int(readU16(at: flOff + 4))
                let y = Int(readU16(at: flOff + 6))
                if w > 0, h > 0, (x > 0 || y > 0) {
                    focusResult = .init(width: w, height: h, x: x, y: y)
                }
                break
            }
        }

        return TIFFWalkDiagnostics(
            isLittleEndian: le,
            ifd0Offset: ifd0,
            ifd0EntryCount: ifd0Count,
            exifIFDOffset: exifIFDOffset,
            exifEntryCount: exifEntryCount,
            makerNoteOffset: makerNoteOffset,
            makerNoteSize: makerNoteSize,
            hasSonyPrefix: hasSonyPrefix,
            sonyIFDOffset: sonyIFDOffset,
            sonyIFDEntryCount: sonyIFDEntryCount,
            sonyAllTags: sonyAllTags,
            focusTagUsed: focusTagUsed,
            focusOffset: focusOffset,
            focusRawBytes: focusRawBytes,
            focusResult: focusResult)
    }

    // MARK: Embedded JPEG locations

    nonisolated func parseEmbeddedJPEGLocations() -> EmbeddedJPEGLocations {
        typealias Loc = EmbeddedJPEGLocations.Location

        guard let ifd0Raw = readU32(at: 4) else { return .init() }
        let ifd0 = Int(ifd0Raw)

        // IFD0: preview JPEG via StripOffsets (0x0111) + StripByteCounts (0x0117).
        // Sony also stores this pair as JPEGInterchangeFormat (0x0201) / Length (0x0202)
        // on some bodies — try both so we work regardless of which tag is used.
        let preview: Loc? = locateJPEG(in: ifd0, offTag: 0x0111, lenTag: 0x0117)
            ?? locateJPEG(in: ifd0, offTag: 0x0201, lenTag: 0x0202)

        // Walk IFD chain: IFD0 → IFD1
        guard ifd0 + 2 <= data.count else { return .init(preview: preview) }
        let ifd0Count = Int(readU16(at: ifd0))
        let ifd1Ptr = ifd0 + 2 + ifd0Count * 12
        guard let ifd1Raw = readU32(at: ifd1Ptr), ifd1Raw > 0 else {
            return .init(preview: preview)
        }
        let ifd1 = Int(ifd1Raw)

        // IFD1: tiny thumbnail via JPEGInterchangeFormat (0x0201) + Length (0x0202).
        let thumbnail: Loc? = locateJPEG(in: ifd1, offTag: 0x0201, lenTag: 0x0202)

        // Walk IFD chain: IFD1 → IFD2
        guard ifd1 + 2 <= data.count else {
            return .init(thumbnail: thumbnail, preview: preview)
        }
        let ifd1Count = Int(readU16(at: ifd1))
        let ifd2Ptr = ifd1 + 2 + ifd1Count * 12
        guard let ifd2Raw = readU32(at: ifd2Ptr), ifd2Raw > 0 else {
            return .init(thumbnail: thumbnail, preview: preview)
        }
        let ifd2 = Int(ifd2Raw)

        // IFD2: full-resolution JPEG via StripOffsets (0x0111) + StripByteCounts (0x0117).
        let fullJPEG: Loc? = locateJPEG(in: ifd2, offTag: 0x0111, lenTag: 0x0117)
            ?? locateJPEG(in: ifd2, offTag: 0x0201, lenTag: 0x0202)

        return .init(thumbnail: thumbnail, preview: preview, fullJPEG: fullJPEG)
    }

    /// Returns a Location by reading two LONG tags from an IFD: one for the file offset,
    /// one for the byte count. Both must be present and non-zero.
    private nonisolated func locateJPEG(in ifdOffset: Int, offTag: UInt16, lenTag: UInt16) -> EmbeddedJPEGLocations.Location? {
        guard let offset = subIFDOffset(in: ifdOffset, tag: offTag),
              let length = subIFDOffset(in: ifdOffset, tag: lenTag),
              offset > 0, length > 0
        else { return nil }
        return .init(offset: offset, length: length)
    }

    // MARK: Binary parsing helpers

    private nonisolated func subIFDOffset(in ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        return readU32(at: valLoc).map(Int.init)
    }

    private nonisolated func tagDataRange(in ifdOffset: Int, tag: UInt16) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset))
        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            if readU16(at: e) == tag {
                let type = Int(readU16(at: e + 2))
                let count = Int(readU32(at: e + 4) ?? 0)
                let sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4]
                let bytes = count * (type < sizes.count ? sizes[type] : 1)

                if bytes <= 4 { return (e + 8, bytes) }
                guard let ptr = readU32(at: e + 8) else { return nil }
                // A1 / A1 II MakerNote IFD entries use absolute file offsets
                // (not relative to MakerNote start) per ExifTool ProcessExif behaviour.
                return (Int(ptr), bytes)
            }
        }
        return nil
    }

    private nonisolated func sonyIFDStart(at offset: Int) -> Int {
        guard offset + 12 <= data.count else { return offset }
        // Check for "SONY DSC " ASCII prefix (9 bytes + 3 null pad = 12 bytes).
        // Read raw bytes — do not use endian-aware readU32 for ASCII magic.
        let isSony = data[offset] == 0x53 && // S
            data[offset + 1] == 0x4F && // O
            data[offset + 2] == 0x4E && // N
            data[offset + 3] == 0x59 // Y
        return isSony ? offset + 12 : offset
    }

    private nonisolated func readU16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return le ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8) :
            (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private nonisolated func readU32(at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return le ? UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24) :
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
