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

struct SonyMakerNoteParser {
    /// Returns "width height x y" calibrated for the Sony A1 sensor.
    nonisolated static func focusLocation(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
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

        // 1. Get Physical Sensor Dimensions (8640x5760 for A1)
        let fullW = readIFDValue(ifdOffset: ifd0, tag: 0x0100) ?? 8640
        let fullH = readIFDValue(ifdOffset: ifd0, tag: 0x0101) ?? 5760

        // 2. Navigate to MakerNote -> AFInfo (Tag 0x9400)
        guard let exifIFD = subIFDOffset(in: ifd0, tag: 0x8769),
              let (mnOffset, _) = tagDataRange(in: exifIFD, tag: 0x927C) else { return nil }

        let ifdStart = sonyIFDStart(at: mnOffset)
        // Find Tag 0x9400 (AFInfo) relative to the MakerNote start
        guard let (afOffset, _) = tagDataRange(in: ifdStart, tag: 0x9400, baseOffset: mnOffset) else { return nil }

        // 3. Extract Dynamic Grid Indices
        // gridX is at offset 8, gridY is at offset 10 within the AF block
        let gridX = Int(readU16(at: afOffset + 8))
        let gridY = Int(readU16(at: afOffset + 10))
        
        // Skip if indices are zero (often indicates focus not locked)
        guard gridX > 0 || gridY > 0 else { return nil }

        // 4. ExifTool-Specific Scaling for Sony ILCE-1
        // These constants translate Sony's internal 0-indexed grid to pixel space
        let gridMaxW: Double = 485.4
        let gridMaxH: Double = 326.6

        let xRatio = Double(fullW) / gridMaxW
        let xVal = (Double(gridX) + 0.15) * xRatio // +0.15 is the A1 horizontal bias
        let finalX = Int(xVal.rounded())

        let yRatio = Double(fullH) / gridMaxH
        let yVal = (Double(gridY) - 0.2) * yRatio  // -0.2 is the A1 vertical bias
        let finalY = Int(yVal.rounded())

        return (fullW, fullH, finalX, finalY)
    }

    // MARK: - Binary Parsing Helpers

    nonisolated private func readIFDValue(ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (offset, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        if let val32 = readU32(at: offset) { return Int(val32) }
        return Int(readU16(at: offset))
    }

    nonisolated private func subIFDOffset(in ifdOffset: Int, tag: UInt16) -> Int? {
        guard let (valLoc, _) = tagDataRange(in: ifdOffset, tag: tag) else { return nil }
        return readU32(at: valLoc).map(Int.init)
    }

    nonisolated private func tagDataRange(in ifdOffset: Int, tag: UInt16, baseOffset: Int? = nil) -> (dataOffset: Int, byteCount: Int)? {
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
                var abs = Int(ptr)
                // Critical: Sony pointers are often relative to MakerNote start
                if let base = baseOffset, abs < base { abs += base }
                return (abs, bytes)
            }
        }
        return nil
    }

    nonisolated private func sonyIFDStart(at offset: Int) -> Int {
        guard offset + 12 <= data.count else { return offset }
        let magic = readU32(at: offset)
        // Check for "SONY DSC " header
        return (magic == 0x594E4F53 || magic == 0x534F4E59) ? offset + 12 : offset
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
