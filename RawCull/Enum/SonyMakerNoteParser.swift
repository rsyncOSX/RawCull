//
//  SonyMakerNoteParser.swift
//  RawCull
//
//  Parses Sony ARW raw files to extract AF focus location natively,
//  without requiring exiftool. Targets Sony A1 (ILCE-1) and A1 Mark II (ILCE-1M2).
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

// MARK: - Parser

enum SonyMakerNoteParser {
    /// Returns "width height x y" calibrated for the Sony A1 sensor.
    nonisolated static func focusLocation(from url: URL) -> String? {
        // Read only the first 4 MB. Sony ARW MakerNote metadata sits well within
        // that range; loading the full ~50 MB RAW file is wasteful on external storage
        // where mmap is unavailable and Data(contentsOf:) falls back to a full read.
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 4 * 1024 * 1024),
              let result = TIFFParser(data: data)?.parseSonyFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
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
        return parser.runDiagnostics()
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
