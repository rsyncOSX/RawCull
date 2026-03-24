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

struct SonyMakerNoteParser {
    /// Returns the focus location as "width height x y" or `nil` if extraction fails.
    nonisolated static func focusLocation(from url: URL) -> String? {
        // Using mappedIfSafe to keep memory footprint low for large RAW files.
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let result = TIFFParser(data: data)?.parseSonyFocusLocation()
        else { return nil }
        return "\(result.width) \(result.height) \(result.x) \(result.y)"
    }
}

// MARK: - TIFF parser
struct TIFFParser {
    let data: Data
    let le: Bool // Sony ARW is little-endian (II), but we check for safety.

    nonisolated init?(data: Data) {
        guard data.count >= 8 else { return nil }
        let b0 = data[0], b1 = data[1]
        
        if b0 == 0x49, b1 == 0x49 {
            le = true
        } else if b0 == 0x4D, b1 == 0x4D {
            le = false
        } else {
            return nil
        }
        
        let magic = TIFFParser.readU16(data, at: 2, le: le)
        guard magic == 42 else { return nil }
        self.data = data
    }

    // MARK: Navigation

    nonisolated func parseSonyFocusLocation() -> (width: Int, height: Int, x: Int, y: Int)? {
        guard let ifd0 = readU32(at: 4).map(Int.init) else { return nil }

        // 1. Find ExifIFD
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769) else { return nil }

        // 2. Find MakerNote (0x927C)
        guard let (mnOffset, _) = tagDataRange(in: exifIFD, tag: 0x927C) else { return nil }

        // 3. Handle Sony MakerNote Header (Variable length/string)
        let ifdStart = sonyIFDStart(at: mnOffset)

        // 4. Find AFInfo (0x9400)
        guard let (afOffset, afBytes) = tagDataRange(in: ifdStart, tag: 0x9400, baseOffset: mnOffset) else { return nil }

        // FocusLocation at byte offset 4 within the block (Standard for A1/A1II)
        guard afBytes >= 12, afOffset + 12 <= data.count else { return nil }

        let width  = Int(readU16(at: afOffset + 4))
        let height = Int(readU16(at: afOffset + 6))
        let x      = Int(readU16(at: afOffset + 8))
        let y      = Int(readU16(at: afOffset + 10))

        guard width > 0, height > 0 else { return nil }
        return (width, height, x, y)
    }

    // MARK: IFD helpers

    nonisolated private func subIFDOffset(in ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        return readU32(at: valLoc).map(Int.init)
    }

    /// - Parameter baseOffset: If provided, helps resolve relative offsets within MakerNotes.
    nonisolated func tagDataRange(in ifdOffset: Int, tag: UInt16, baseOffset: Int? = nil) -> (dataOffset: Int, byteCount: Int)? {
        guard ifdOffset + 2 <= data.count else { return nil }
        let entryCount = Int(readU16(at: ifdOffset))
        
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
            var abs = Int(ptr)
            
            // HEURISTIC: Sony sometimes uses relative offsets inside MakerNotes.
            // If the pointer is very small relative to the file size, it's likely
            // relative to the start of the MakerNote (baseOffset).
            if let base = baseOffset, abs < base {
                abs += base
            }
            
            guard abs + totalBytes <= data.count else { return nil }
            return (abs, totalBytes)
        }
        return nil
    }

    /// Sony MakerNote IFDs can start with "SONY DSC \0", "SONY CAM \0",
    /// or nothing at all (A1). This checks for a valid IFD count to decide.
    nonisolated func sonyIFDStart(at offset: Int) -> Int {
        guard offset + 12 <= data.count else { return offset }
        
        // If the first 4 bytes look like ASCII "SONY", skip the 12-byte header.
        let magic = readU32(at: offset)
        if magic == 0x594E4F53 || magic == 0x534F4E59 { // "SONY" in LE or BE
            return offset + 12
        }
        return offset
    }

    // MARK: Low-level readers

    nonisolated func readU16(at offset: Int) -> UInt16 {
        TIFFParser.readU16(data, at: offset, le: le)
    }

    nonisolated func readU32(at offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        // Switched from .reduce to direct bitwise for performance
        let b = data[offset..<(offset+4)]
        if le {
            return UInt32(b[offset]) | (UInt32(b[offset+1]) << 8) | (UInt32(b[offset+2]) << 16) | (UInt32(b[offset+3]) << 24)
        } else {
            return (UInt32(b[offset]) << 24) | (UInt32(b[offset+1]) << 16) | (UInt32(b[offset+2]) << 8) | UInt32(b[offset+3])
        }
    }

    nonisolated static func readU16(_ d: Data, at offset: Int, le: Bool) -> UInt16 {
        guard offset + 2 <= d.count else { return 0 }
        let a = UInt16(d[offset]), b = UInt16(d[offset + 1])
        return le ? a | (b << 8) : (a << 8) | b
    }

    nonisolated private func ifdTypeBytes(_ type: Int) -> Int {
        switch type {
        case 1, 2, 6, 7: return 1   // BYTE, ASCII, SBYTE, UNDEFINED
        case 3, 8:        return 2   // SHORT, SSHORT
        case 4, 9, 11, 13: return 4  // LONG, SLONG, FLOAT, IFD
        case 5, 10, 12:   return 8   // RATIONAL, SRATIONAL, DOUBLE
        default:          return 1
        }
    }
}
