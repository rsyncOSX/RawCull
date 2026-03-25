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

struct SonyMakerNoteParser {
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
}

private struct TIFFParser {
    let data: Data
    let le: Bool

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        if b0 == 0x49 && b1 == 0x49 { le = true }
        else if b0 == 0x4D && b1 == 0x4D { le = false }
        else { return nil }
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
        let flTag: UInt16 = tagDataRange(in: ifdStart, tag: 0x2027) != nil ? 0x2027 : 0x204a
        guard let (flOffset, flSize) = tagDataRange(in: ifdStart, tag: flTag),
              flSize >= 8 else { return nil }

        let width  = Int(readU16(at: flOffset + 0))
        let height = Int(readU16(at: flOffset + 2))
        let x      = Int(readU16(at: flOffset + 4))
        let y      = Int(readU16(at: flOffset + 6))

        guard width > 0, height > 0, x > 0 || y > 0 else { return nil }

        return (width, height, x, y)
    }

    // MARK: - Binary Parsing Helpers

    nonisolated private func subIFDOffset(in ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        return readU32(at: valLoc).map(Int.init)
    }

    nonisolated private func tagDataRange(in ifdOffset: Int, tag: UInt16) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset))
        for i in 0 ..< entryCount {
            let e = ifdOffset + 2 + i * 12
            guard e + 12 <= data.count else { break }
            if readU16(at: e) == tag {
                let type = Int(readU16(at: e + 2))
                let count = Int(readU32(at: e + 4) ?? 0)
                let sizes = [0,1,1,2,4,8,1,1,2,4,8,4,8,4]
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

    nonisolated private func sonyIFDStart(at offset: Int) -> Int {
        guard offset + 12 <= data.count else { return offset }
        // Check for "SONY DSC " ASCII prefix (9 bytes + 3 null pad = 12 bytes).
        // Read raw bytes — do not use endian-aware readU32 for ASCII magic.
        let isSony = data[offset]   == 0x53 &&  // S
                     data[offset+1] == 0x4F &&  // O
                     data[offset+2] == 0x4E &&  // N
                     data[offset+3] == 0x59     // Y
        return isSony ? offset + 12 : offset
    }

    nonisolated private func readU16(at offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return le ? UInt16(data[offset]) | (UInt16(data[offset+1]) << 8) :
                    (UInt16(data[offset]) << 8) | UInt16(data[offset+1])
    }

    nonisolated private func readU32(at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        return le ? UInt32(data[offset]) | (UInt32(data[offset+1]) << 8) | (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24) :
                    (UInt32(data[offset]) << 24) | (UInt32(data[offset+1]) << 16) | (UInt32(data[offset+2]) << 8) | UInt32(data[offset+3])
    }
}
