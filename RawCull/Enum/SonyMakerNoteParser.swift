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
//      → Sony MakerNote IFD → AFInfo (tag 0x9400)
//
//  Within the AFInfo binary block, ExifTool's Sony.pm Tag9400a table
//  (used for ILCE-1 and ILCE-1M2) defines FORMAT = 'int16u' with:
//    index 2 → FocusLocation[4]  (four consecutive uint16 values)
//  meaning byte offset 4 within the block holds:
//    [imageWidth, imageHeight, afCenterX, afCenterY]
//
//  Sony MakerNote IFD entries use absolute file offsets (not relative to
//  the MakerNote start), consistent with ExifTool's ProcessExif behaviour.
//

import Foundation

// MARK: - Public API

/// Returns the focus location as "width height x y" — the same format
/// that `FocusPoint(focusLocation:)` parses — or `nil` if extraction fails.
struct SonyMakerNoteParser {
    // nonisolated: pure file I/O — must not inherit the project-wide @MainActor default
    nonisolated static func focusLocation(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let result = TIFFParser(data: data)?.parseSonyFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
    }
}

// MARK: - TIFF parser

private struct TIFFParser {

    let data: Data
    let le: Bool   // true = little-endian (Sony ARW is always LE)

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        if b0 == 0x49, b1 == 0x49 {
            le = true
        } else if b0 == 0x4D, b1 == 0x4D {
            le = false
        } else {
            return nil // not a TIFF file
        }
        // Validate TIFF magic number (42 / 0x002A)
        let magic = TIFFParser.readU16(data, at: 2, le: le)
        guard magic == 42 else { return nil }
        self.data = data
    }

    // MARK: Navigation

    nonisolated func parseSonyFocusLocation() -> (width: Int, height: Int, x: Int, y: Int)? {
        // IFD0 offset stored at bytes 4–7
        guard let ifd0 = readU32(at: 4).map(Int.init) else { return nil }

        // IFD0 → ExifIFD (tag 0x8769)
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769) else { return nil }

        // ExifIFD → MakerNote (tag 0x927C)
        // For large UNDEFINED values, tagDataRange() returns the absolute file offset.
        guard let (mnOffset, _) = tagDataRange(in: exifIFD, tag: 0x927C) else { return nil }

        // Sony A1 MakerNote starts directly with an IFD (no "SONY DSC " header).
        // Detect the optional header and skip it for robustness with other models.
        let ifdStart = sonyIFDStart(at: mnOffset)

        // Sony MakerNote IFD → AFInfo (tag 0x9400)
        guard let (afOffset, afBytes) = tagDataRange(in: ifdStart, tag: 0x9400) else { return nil }

        // FocusLocation = uint16[4] at byte offset 4 within the AFInfo block:
        //   bytes  4–5  → imageWidth
        //   bytes  6–7  → imageHeight
        //   bytes  8–9  → afCenterX
        //   bytes 10–11 → afCenterY
        guard afBytes >= 12, afOffset + 12 <= data.count else { return nil }

        let width  = Int(readU16(at: afOffset + 4))
        let height = Int(readU16(at: afOffset + 6))
        let x      = Int(readU16(at: afOffset + 8))
        let y      = Int(readU16(at: afOffset + 10))

        guard width > 0, height > 0 else { return nil }
        return (width, height, x, y)
    }

    // MARK: IFD helpers

    /// Returns the offset of the sub-IFD that a LONG-typed pointer tag contains.
    nonisolated private func subIFDOffset(in ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        return readU32(at: valLoc).map(Int.init)
    }

    /// Returns `(dataOffset, byteCount)` for a tag inside an IFD.
    ///
    /// - Inline values (total ≤ 4 bytes): `dataOffset` points to the value field
    ///   within the 12-byte IFD entry.
    /// - External values (total > 4 bytes): `dataOffset` is the absolute file offset
    ///   stored in the value field (Sony uses absolute offsets throughout its MakerNote).
    nonisolated private func tagDataRange(in ifdOffset: Int, tag: UInt16) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset))
        guard entryCount > 0, entryCount < 2048 else { return nil }

        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            guard readU16(at: e) == tag else { continue }

            let type       = Int(readU16(at: e + 2))
            let itemCount  = Int(readU32(at: e + 4) ?? 0)
            let totalBytes = itemCount * ifdTypeBytes(type)

            if totalBytes <= 4 {
                return (e + 8, totalBytes)
            }
            guard let ptr = readU32(at: e + 8) else { return nil }
            let abs = Int(ptr)
            guard abs + totalBytes <= data.count else { return nil }
            return (abs, totalBytes)
        }
        return nil
    }

    /// Skips the optional "SONY DSC \0\0\0" (12-byte) header that older Sony
    /// cameras prepend to their MakerNote IFD. A1 has no such header.
    nonisolated private func sonyIFDStart(at offset: Int) -> Int {
        guard offset + 9 <= data.count else { return offset }
        if data[offset ..< offset + 9] == Data("SONY DSC ".utf8) {
            return offset + 12
        }
        return offset
    }

    // MARK: Low-level readers (instance — use self.data and self.le)

    nonisolated private func readU16(at offset: Int) -> UInt16 {
        TIFFParser.readU16(data, at: offset, le: le)
    }

    nonisolated private func readU32(at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return TIFFParser.readU32(data, at: offset, le: le)
    }

    // MARK: Low-level readers (static — used before self is fully initialised)

    nonisolated static func readU16(_ d: Data, at offset: Int, le: Bool) -> UInt16 {
        guard offset + 2 <= d.count else { return 0 }
        let a = UInt16(d[offset]), b = UInt16(d[offset + 1])
        return le ? a | (b << 8) : (a << 8) | b
    }

    nonisolated static func readU32(_ d: Data, at offset: Int, le: Bool) -> UInt32 {
        guard offset + 4 <= d.count else { return 0 }
        return (0 ..< 4).reduce(0) { acc, i in
            let byte = UInt32(d[offset + i])
            return acc | (le ? byte << (i * 8) : byte << ((3 - i) * 8))
        }
    }

    /// Returns the byte size of a single value for the given TIFF type code.
    nonisolated private func ifdTypeBytes(_ type: Int) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1   // BYTE, ASCII, SBYTE, UNDEFINED
        case 3, 8:        return 2   // SHORT, SSHORT
        case 4, 9, 11:    return 4   // LONG, SLONG, FLOAT
        case 5, 10, 12:   return 8   // RATIONAL, SRATIONAL, DOUBLE
        default:          return 1
        }
    }
}
