//
//  NikonMakerNoteParser.swift
//  RawCull
//
//  Parses Nikon NEF raw files to extract AF focus location natively.
//  Pilot target: Nikon Z9 (AFInfoVersion "0300"+). Older DSLRs may fall
//  through and return nil until their AFInfo2 layout is added.
//
//  Technical background
//  ─────────────────────
//  NEF is TIFF-based. Focus location lives in:
//    TIFF IFD0 → ExifIFD (tag 0x8769) → MakerNote (tag 0x927C)
//      → "Nikon\0" + 4-byte version + inner TIFF header
//      → Nikon IFD → AFInfo2 (tag 0x00B7)
//
//  Nikon Type-3 MakerNote layout (Z-series and most modern DSLRs):
//    Offset 0..5   "Nikon\0"                  6 bytes ASCII signature
//    Offset 6..9   version (e.g. 0x02 0x11 0x00 0x00)
//    Offset 10..   inner TIFF header (II/MM + 0x2A + IFD0 offset)
//  Inner TIFF offsets are RELATIVE to the MakerNote TIFF header start
//  (MakerNote base + 10), NOT to the file start.
//
//  AFInfo2 (tag 0x00B7) is an UNDEFINED blob. For AFInfoVersion "0300"
//  and later (Z-series), the relevant fields are uint16 LE:
//    0x26 (38): AFImageWidth
//    0x28 (40): AFImageHeight
//    0x2A (42): AFAreaXPosition   (center of AF area, pixel coords)
//    0x2C (44): AFAreaYPosition
//    0x2E (46): AFAreaWidth
//    0x30 (48): AFAreaHeight
//

import Foundation

// MARK: - Embedded JPEG locations

/// Absolute file offsets for JPEGs embedded in a Nikon NEF.
/// Used as a binary fallback when ImageIO does not expose the preview JPEG as
/// a sub-image index (the common case for NEF, where the full-res preview
/// lives inside a SubIFD chain rather than at a top-level image index).
struct NEFEmbeddedJPEGLocations {
    struct Location {
        let offset: Int
        let length: Int
    }

    /// Largest Compression=6 SubIFD referenced by IFD0 tag 0x014A.
    let preview: Location?
    /// IFD1 preview JPEG (JPEGInterchangeFormat / Length), when present.
    let ifd1JPEG: Location?

    nonisolated init(preview: Location? = nil, ifd1JPEG: Location? = nil) {
        self.preview = preview
        self.ifd1JPEG = ifd1JPEG
    }
}

enum NikonMakerNoteParser {
    /// Returns "width height x y" for the AF focus location encoded in the
    /// Nikon MakerNote's AFInfo2 tag. Shape matches `SonyMakerNoteParser.focusLocation`
    /// so `ScanFiles.parseFocusNormalized` consumes both identically.
    nonisolated static func focusLocation(from url: URL) -> String? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        // Fast path: first 4 MB covers the MakerNote for typical NEF files.
        guard let data = try? fh.read(upToCount: 4 * 1024 * 1024) else { return nil }
        if let result = NikonTIFFParser(data: data)?.parseAFFocusLocation() {
            return "\(result.width) \(result.height) \(result.x) \(result.y)"
        }

        // Slow path: full-file read in case the MakerNote falls beyond the
        // 4 MB window on some bodies (parallel to SonyMakerNoteParser).
        try? fh.seek(toOffset: 0)
        guard let full = try? fh.read(upToCount: Int.max),
              full.count > data.count,
              let result = NikonTIFFParser(data: full)?.parseAFFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
    }

    /// Walks the NEF's TIFF IFD structures and returns absolute file offsets for
    /// the embedded JPEG(s). Fast path reads the first 1 MB (enough to cover
    /// IFD0/SubIFDs on all tested Z-series bodies); slow path re-reads the full
    /// file if the fast-path walk yielded nothing.
    nonisolated static func embeddedJPEGLocations(from url: URL) -> NEFEmbeddedJPEGLocations? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }

        guard let data = try? fh.read(upToCount: 1024 * 1024),
              let parser = NikonTIFFParser(data: data)
        else { return nil }
        let initial = parser.parseEmbeddedJPEGLocations()
        if initial.preview != nil || initial.ifd1JPEG != nil { return initial }

        try? fh.seek(toOffset: 0)
        guard let full = try? fh.read(upToCount: Int.max),
              full.count > data.count,
              let fullParser = NikonTIFFParser(data: full)
        else { return initial }
        return fullParser.parseEmbeddedJPEGLocations()
    }

    /// Reads raw bytes for an embedded JPEG from the file at the given absolute offset.
    nonisolated static func readEmbeddedJPEGData(
        at location: NEFEmbeddedJPEGLocations.Location,
        from url: URL,
    ) -> Data? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(location.offset))
        return try? fh.read(upToCount: location.length)
    }
}

// MARK: - TIFF + Nikon MakerNote parser

private struct NikonTIFFParser {
    let data: Data
    let le: Bool // outer (file) endianness

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        if b0 == 0x49, b1 == 0x49 { le = true } else if b0 == 0x4D, b1 == 0x4D { le = false } else { return nil }
        self.data = data
    }

    /// Walks IFD0 → ExifIFD → MakerNote, detects the Nikon Type-3 signature,
    /// then parses the inner TIFF to find AFInfo2 and extract AF coordinates.
    nonisolated func parseAFFocusLocation() -> (width: Int, height: Int, x: Int, y: Int)? {
        guard let ifd0 = readU32(at: 4, littleEndian: le).map(Int.init) else { return nil }

        // IFD0 → ExifIFD (tag 0x8769 is a LONG pointer to the ExifIFD offset)
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769, littleEndian: le),
              let (mnOffset, mnSize) = tagDataRange(in: exifIFD, tag: 0x927C, littleEndian: le),
              mnSize >= 18, // "Nikon\0" + 4 version + min inner TIFF header (8)
              mnOffset + 18 <= data.count
        else { return nil }

        // Detect the Nikon Type-3 signature: ASCII "Nikon\0".
        let sig: [UInt8] = [0x4E, 0x69, 0x6B, 0x6F, 0x6E, 0x00] // "Nikon\0"
        for (i, b) in sig.enumerated() where data[mnOffset + i] != b {
            return nil
        }

        // Inner TIFF header starts 10 bytes into the MakerNote.
        // (6 bytes "Nikon\0" + 4 bytes version)
        let innerTIFF = mnOffset + 10
        guard innerTIFF + 8 <= data.count else { return nil }

        let innerLE: Bool
        let ib0 = data[innerTIFF], ib1 = data[innerTIFF + 1]
        if ib0 == 0x49, ib1 == 0x49 { innerLE = true } else if ib0 == 0x4D, ib1 == 0x4D { innerLE = false } else { return nil }

        // Inner TIFF magic 0x2A at offset +2 (skip — optional sanity check)
        guard let ifdRelRaw = readU32(at: innerTIFF + 4, littleEndian: innerLE) else { return nil }
        let nikonIFD = innerTIFF + Int(ifdRelRaw) // inner offsets are relative to innerTIFF

        // Find AFInfo2 (tag 0x00B7). Offsets inside the Nikon IFD are relative to innerTIFF.
        guard let (afRel, afSize) = tagDataRange(
            in: nikonIFD,
            tag: 0x00B7,
            littleEndian: innerLE,
            offsetBase: innerTIFF,
        ), afSize >= 0x38 // need at least through offset 0x30 + 2
        else { return nil }

        let afStart = afRel // already absolute in `data`
        guard afStart + 0x32 <= data.count else { return nil }

        // AFInfoVersion at offset 0: 4 ASCII bytes. "0300"+ is Z-series and modern
        // DSLRs; older versions (0100, 0101, 0102, 0103) use a different layout
        // and are deferred until fixtures are available.
        let v0 = data[afStart + 0]
        let v1 = data[afStart + 1]
        let v2 = data[afStart + 2]
        let v3 = data[afStart + 3]
        // Accept "0300", "0301", "0302", "0400" and similar — first char '0', second >= '3'.
        guard v0 == 0x30, v1 >= 0x33, v1 <= 0x39,
              isASCIIDigit(v2), isASCIIDigit(v3) else { return nil }

        // Z-series AFInfo2 layout (matches the file-level doc block):
        //   0x26  AFImageWidth       (uint16)
        //   0x28  AFImageHeight      (uint16)
        //   0x2A  AFAreaXPosition    (uint16, centre of AF area, pixel coords)
        //   0x2C  AFAreaYPosition    (uint16)
        // Endianness is the inner TIFF's, which may differ from the outer file.
        let width = Int(readU16(at: afStart + 0x26, littleEndian: innerLE))
        let height = Int(readU16(at: afStart + 0x28, littleEndian: innerLE))
        let x = Int(readU16(at: afStart + 0x2A, littleEndian: innerLE))
        let y = Int(readU16(at: afStart + 0x2C, littleEndian: innerLE))

        // Sanity gate: dimensions must be plausible for modern bodies,
        // and focus point must fall within the image.
        guard width >= 2000, height >= 1000,
              x >= 0, y >= 0, x <= width, y <= height,
              x > 0 || y > 0 else { return nil }

        return (width, height, x, y)
    }

    // MARK: - Embedded JPEG locations

    /// Walks IFD0 → SubIFDs (tag 0x014A) → picks the largest SubIFD whose
    /// Compression (0x0103) == 6 (OldJPEG), reading the JPEG location from
    /// StripOffsets/StripByteCounts (0x0111/0x0117), falling back to
    /// JPEGInterchangeFormat/Length (0x0201/0x0202). Also probes IFD1 for a
    /// secondary preview. All offsets are absolute within the outer file.
    nonisolated func parseEmbeddedJPEGLocations() -> NEFEmbeddedJPEGLocations {
        typealias Loc = NEFEmbeddedJPEGLocations.Location

        guard let ifd0Raw = readU32(at: 4, littleEndian: le) else { return .init() }
        let ifd0 = Int(ifd0Raw)

        // IFD0 → SubIFDs (tag 0x014A). For count N > 1, the tag's value is a
        // pointer to a LONG[N] array of IFD offsets. For N == 1 with inline
        // storage (bytes <= 4) the value itself *is* the sub-IFD offset.
        let subIFDOffsets = readSubIFDOffsets(in: ifd0, tag: 0x014A, littleEndian: le)

        var best: Loc?
        for sub in subIFDOffsets {
            guard let loc = jpegLocation(in: sub, littleEndian: le) else { continue }
            if best == nil || loc.length > (best?.length ?? 0) {
                best = loc
            }
        }

        // IFD1 (via NextIFD pointer at end of IFD0) — some bodies store a
        // preview JPEG here addressed via JPEGInterchangeFormat (0x0201).
        var ifd1JPEG: Loc?
        if ifd0 + 2 <= data.count {
            let ifd0Count = Int(readU16(at: ifd0, littleEndian: le))
            let nextIFDPtr = ifd0 + 2 + ifd0Count * 12
            if let ifd1Raw = readU32(at: nextIFDPtr, littleEndian: le), ifd1Raw > 0 {
                let ifd1 = Int(ifd1Raw)
                ifd1JPEG = locateJPEG(in: ifd1, offTag: 0x0201, lenTag: 0x0202, littleEndian: le)
                    ?? locateJPEG(in: ifd1, offTag: 0x0111, lenTag: 0x0117, littleEndian: le)
            }
        }

        return .init(preview: best, ifd1JPEG: ifd1JPEG)
    }

    /// Resolves the list of SubIFD offsets stored under `tag` in the IFD at
    /// `ifdOffset`. Returns an empty array if the tag is missing or malformed.
    private nonisolated func readSubIFDOffsets(in ifdOffset: Int, tag: UInt16, littleEndian: Bool) -> [Int] {
        guard ifdOffset + 2 <= data.count else { return [] }
        let entryCount = Int(readU16(at: ifdOffset, littleEndian: littleEndian))
        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            if readU16(at: e, littleEndian: littleEndian) == tag {
                let count = Int(readU32(at: e + 4, littleEndian: littleEndian) ?? 0)
                // SubIFDs are TIFF type 4 (LONG, 4 bytes each) or type 13 (IFD, 4 bytes).
                // 4 bytes fit inline when count == 1; otherwise the value is a pointer
                // to a LONG[count] array.
                if count == 1 {
                    guard let v = readU32(at: e + 8, littleEndian: littleEndian) else { return [] }
                    return [Int(v)]
                }
                guard let arrayPtr = readU32(at: e + 8, littleEndian: littleEndian) else { return [] }
                var offsets: [Int] = []
                offsets.reserveCapacity(count)
                for j in 0 ..< count {
                    guard let off = readU32(at: Int(arrayPtr) + j * 4, littleEndian: littleEndian) else { break }
                    offsets.append(Int(off))
                }
                return offsets
            }
        }
        return []
    }

    /// Extracts a JPEG location from a SubIFD if its Compression tag (0x0103)
    /// is 6 (OldJPEG) and it carries a usable offset/length pair.
    private nonisolated func jpegLocation(in ifdOffset: Int, littleEndian: Bool) -> NEFEmbeddedJPEGLocations.Location? {
        // Compression must be 6 (OldJPEG).
        guard let (compLoc, compSize) = tagDataRange(in: ifdOffset, tag: 0x0103, littleEndian: littleEndian),
              compSize >= 2,
              readU16(at: compLoc, littleEndian: littleEndian) == 6
        else { return nil }

        // Prefer StripOffsets/StripByteCounts; fall back to JPEGInterchangeFormat/Length.
        return locateJPEG(in: ifdOffset, offTag: 0x0111, lenTag: 0x0117, littleEndian: littleEndian)
            ?? locateJPEG(in: ifdOffset, offTag: 0x0201, lenTag: 0x0202, littleEndian: littleEndian)
    }

    /// Reads two LONG tags (offset + byte count) from an IFD and returns them
    /// as a Location. Both must be present and non-zero.
    private nonisolated func locateJPEG(
        in ifdOffset: Int,
        offTag: UInt16,
        lenTag: UInt16,
        littleEndian: Bool,
    ) -> NEFEmbeddedJPEGLocations.Location? {
        guard let offset = subIFDOffset(in: ifdOffset, tag: offTag, littleEndian: littleEndian),
              let length = subIFDOffset(in: ifdOffset, tag: lenTag, littleEndian: littleEndian),
              offset > 0, length > 0
        else { return nil }
        return .init(offset: offset, length: length)
    }

    // MARK: - Binary helpers

    private nonisolated func isASCIIDigit(_ b: UInt8) -> Bool {
        b >= 0x30 && b <= 0x39
    }

    private nonisolated func subIFDOffset(in ifdOffset: Int, tag: UInt16, littleEndian: Bool) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag, littleEndian: littleEndian) else { return nil }
        return readU32(at: valLoc, littleEndian: littleEndian).map(Int.init)
    }

    /// Locates the data range for an IFD entry's value. For offset-style values
    /// (bytes > 4), the returned `dataOffset` is absolute within `data`, computed
    /// as `offsetBase + relativeOffset` when a non-nil base is given (used for
    /// Nikon inner-TIFF offsets which are relative to the inner TIFF header).
    /// When `offsetBase` is nil, the stored offset is treated as absolute
    /// (matches Sony MakerNote ProcessExif behaviour).
    ///
    /// TIFF IFD entry layout (12 bytes):
    ///
    ///     [0..1]  tag        (UInt16)
    ///     [2..3]  type       (UInt16 index into `sizes` below)
    ///     [4..7]  count      (UInt32, elements)
    ///     [8..11] value/ptr  (UInt32 — inline value if count·sizes[type] ≤ 4,
    ///                         otherwise a file offset to the real bytes)
    ///
    /// `sizes` maps TIFF type index → bytes per element:
    ///
    ///     idx:    0  1  2  3  4  5  6  7  8  9  10 11 12 13
    ///     type:   -  B  A  S  L  R  sB U  sS sL sR F  D  IFD
    ///     bytes:  0  1  1  2  4  8  1  1  2  4  8  4  8  4
    ///
    /// Endianness of all reads follows the caller-provided `littleEndian` flag
    /// (may differ between the outer file TIFF and the Nikon inner TIFF).
    private nonisolated func tagDataRange(
        in ifdOffset: Int,
        tag: UInt16,
        littleEndian: Bool,
        offsetBase: Int? = nil,
    ) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset, littleEndian: littleEndian))
        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            if readU16(at: e, littleEndian: littleEndian) == tag {
                let type = Int(readU16(at: e + 2, littleEndian: littleEndian))
                let count = Int(readU32(at: e + 4, littleEndian: littleEndian) ?? 0)
                let sizes = [0, 1, 1, 2, 4, 8, 1, 1, 2, 4, 8, 4, 8, 4]
                let bytes = count * (type < sizes.count ? sizes[type] : 1)

                if bytes <= 4 { return (e + 8, bytes) }
                guard let ptr = readU32(at: e + 8, littleEndian: littleEndian) else { return nil }
                let base = offsetBase ?? 0
                return (base + Int(ptr), bytes)
            }
        }
        return nil
    }

    private nonisolated func readU16(at offset: Int, littleEndian: Bool) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return littleEndian ? UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8) :
            (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private nonisolated func readU32(at offset: Int, littleEndian: Bool) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return littleEndian ?
            UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24) :
            (UInt32(data[offset]) << 24) | (UInt32(data[offset + 1]) << 16) | (UInt32(data[offset + 2]) << 8) | UInt32(data[offset + 3])
    }
}
