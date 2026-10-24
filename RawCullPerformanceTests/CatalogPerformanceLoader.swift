import AppKit
import Foundation
@testable import RawCull

/// Forwards every operation to the production parser; only adds measurements.
actor CatalogPerformanceLoader: RawImageLoading {
    let journal: CatalogPerformanceJournal
    private let base = RawParserKitImageLoader.shared

    init(journal: CatalogPerformanceJournal) {
        self.journal = journal
    }

    func fileMetadata(for url: URL) async -> RawImageFileMetadata? {
        await journal.started("metadata")
        let start = ProcessInfo.processInfo.systemUptime
        let result = await base.fileMetadata(for: url)
        await journal.finished("metadata")
        await journal.record("metadata.file", since: start, succeeded: result != nil, detail: url.lastPathComponent)
        return result
    }

    func thumbnailImage(for url: URL, maxPixelSize: Int) async -> NSImage? {
        await journal.started("thumbnailImage")
        let start = ProcessInfo.processInfo.systemUptime
        let result = await base.thumbnailImage(for: url, maxPixelSize: maxPixelSize)
        await journal.finished("thumbnailImage")
        await journal.record("decode.preload", since: start, succeeded: result != nil, detail: url.lastPathComponent)
        return result
    }

    func thumbnailCGImage(for url: URL, maxPixelSize: Int) async -> CGImage? {
        await journal.started("thumbnailCGImage")
        let start = ProcessInfo.processInfo.systemUptime
        let result = await base.thumbnailCGImage(for: url, maxPixelSize: maxPixelSize)
        await journal.finished("thumbnailCGImage")
        await journal.record("decode.interactive", since: start, succeeded: result != nil, detail: url.lastPathComponent)
        return result
    }

    func previewCGImage(for url: URL) async -> CGImage? {
        await journal.started("preview")
        let start = ProcessInfo.processInfo.systemUptime
        let result = await base.previewCGImage(for: url)
        await journal.finished("preview")
        await journal.record("decode.zoomPreview", since: start, succeeded: result != nil, detail: url.lastPathComponent)
        return result
    }

    func embeddedPreviewJPEGData(for url: URL, matchingPixelWidth width: Int, height: Int) async -> Data? {
        await base.embeddedPreviewJPEGData(for: url, matchingPixelWidth: width, height: height)
    }
}
