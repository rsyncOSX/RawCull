import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeDiagnosticFileItem(url: URL, size: Int64? = nil) throws -> FileItem {
    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
    return FileItem(
        url: url,
        name: url.lastPathComponent,
        size: size ?? Int64(values.fileSize ?? 0),
        dateModified: values.contentModificationDate ?? Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private func makeSyntheticDiagnosticARW() throws -> URL {
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

    bytes += preview
    bytes += thumbnail
    bytes += full

    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".arw")
    try Data(bytes).write(to: url)
    return url
}

@MainActor
struct RawFileDiagnosticsTests {
    @Test
    func `log includes file identity format and Sony embedded JPEG locations`() throws {
        let url = try makeSyntheticDiagnosticARW()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try makeDiagnosticFileItem(url: url)

        let log = RawFileDiagnostics.log(for: file)

        #expect(log.contains("name: \(url.lastPathComponent)"))
        #expect(log.contains("format: Sony ARW"))
        #expect(log.contains("PARSER TRACE"))
        #expect(log.contains("parser: Sony embedded JPEG locations"))
        #expect(log.contains("sony.thumbnail: offset="))
        #expect(log.contains("sony.preview: offset="))
        #expect(log.contains("sony.fullJPEG: offset="))
        #expect(log.contains("length=6"))
        #expect(log.contains("length=7"))
        #expect(log.contains("length=8"))
    }

    @Test
    func `unsupported extension logs explicit error`() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".txt")
        try Data("not raw".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try makeDiagnosticFileItem(url: url)

        let log = RawFileDiagnostics.log(for: file)

        #expect(log.contains("extension: txt"))
        #expect(log.contains("ERROR: unsupported RAW extension"))
    }
}
