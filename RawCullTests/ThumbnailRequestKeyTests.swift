import AppKit
import Foundation
@testable import RawCull
import Testing

private func makeThumbnailIdentityTestRoot(_ name: String = #function) throws -> URL {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullThumbnailIdentityTests", isDirectory: true)
        .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeThumbnailIdentityTestCGImage() throws -> CGImage {
    guard let context = CGContext(
        data: nil,
        width: 32,
        height: 24,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else {
        throw ThumbnailFingerprintError.metadataUnavailable
    }
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
    return try #require(context.makeImage())
}

struct ThumbnailRequestKeyTests {
    @Test
    func `same source metadata and representation produce same key`() {
        let date = Date(timeIntervalSince1970: 1_725_000_000.1234)
        let firstURL = URL(fileURLWithPath: "/tmp/catalog/../catalog/image.arw")
        let secondURL = URL(fileURLWithPath: "/tmp/catalog/image.arw")

        let first = makeThumbnailRequestKey(
            url: firstURL,
            fileSize: 42,
            modificationDate: date,
            requestedMaxPixelSize: 1_616,
        )
        let second = makeThumbnailRequestKey(
            url: secondURL,
            fileSize: 42,
            modificationDate: date,
            requestedMaxPixelSize: 1_616,
        )

        #expect(first == second)
    }

    @Test
    func `replacing bytes at same path changes source identity`() {
        let url = URL(fileURLWithPath: "/tmp/catalog/replaced.arw")
        let first = makeThumbnailRequestKey(
            url: url,
            fileSize: 100,
            modificationDate: Date(timeIntervalSince1970: 10),
        )
        let replaced = makeThumbnailRequestKey(
            url: url,
            fileSize: 101,
            modificationDate: Date(timeIntervalSince1970: 11),
        )

        #expect(first != replaced)
    }

    @Test
    func `URL metadata boundary rejects a missing source`() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).arw")

        #expect(throws: (any Error).self) {
            try ThumbnailSourceFingerprint.readingMetadata(for: missing)
        }
    }

    @Test
    func `grid representation cannot satisfy preview and larger preview can satisfy smaller preview`() {
        let grid = ThumbnailRepresentation(purpose: .grid, requestedMaxPixelSize: 200)
        let largePreview = ThumbnailRepresentation(purpose: .preview, requestedMaxPixelSize: 1_616)
        let smallPreview = ThumbnailRepresentation(purpose: .preview, requestedMaxPixelSize: 1_024)

        #expect(!grid.canSatisfy(request: smallPreview, decodedMaxPixelSize: 200))
        #expect(largePreview.canSatisfy(request: smallPreview, decodedMaxPixelSize: 1_616))
        #expect(!largePreview.canSatisfy(request: smallPreview, decodedMaxPixelSize: 800))
    }

    @Test
    func `two hundred pixel grid artifact never satisfies preview disk request`() async throws {
        let root = try makeThumbnailIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let source = ThumbnailSourceFingerprint(
            url: URL(fileURLWithPath: "/tmp/separate-representations.arw"),
            fileSize: 10,
            modificationDate: Date(timeIntervalSince1970: 20),
        )
        let gridKey = ThumbnailRequestKey(
            source: source,
            purpose: .grid,
            requestedMaxPixelSize: 200,
        )
        let previewKey = ThumbnailRequestKey(
            source: source,
            purpose: .preview,
            requestedMaxPixelSize: 1_024,
        )
        let data = try #require(DiskCacheManager.jpegData(from: makeThumbnailIdentityTestCGImage()))

        await cache.save(data, for: gridKey)

        #expect(gridKey != previewKey)
        #expect(await cache.load(for: previewKey) == nil)
    }

    @Test
    func `disk cache ignores old schema identity`() async throws {
        let root = try makeThumbnailIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let url = URL(fileURLWithPath: "/tmp/schema-source.arw")
        let oldKey = makeThumbnailRequestKey(url: url, schemaVersion: 2)
        let currentKey = makeThumbnailRequestKey(url: url)
        let data = try #require(DiskCacheManager.jpegData(from: makeThumbnailIdentityTestCGImage()))

        await cache.save(data, for: oldKey)

        #expect(await cache.load(for: currentKey) == nil)
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
    }

    @Test
    func `cache clearing removes old and current schema artifacts`() async throws {
        let root = try makeThumbnailIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let url = URL(fileURLWithPath: "/tmp/clear-schema-source.arw")
        let oldKey = makeThumbnailRequestKey(url: url, schemaVersion: 2)
        let currentKey = makeThumbnailRequestKey(url: url)
        let data = try #require(DiskCacheManager.jpegData(from: makeThumbnailIdentityTestCGImage()))

        await cache.save(data, for: oldKey)
        await cache.save(data, for: currentKey)
        await cache.pruneCache(maxAgeInDays: 0)

        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }

    @Test
    func `cancelled disk save leaves no incomplete artifact`() async throws {
        let root = try makeThumbnailIdentityTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let key = makeThumbnailRequestKey(url: URL(fileURLWithPath: "/tmp/cancelled-save.arw"))
        let data = try #require(DiskCacheManager.jpegData(from: makeThumbnailIdentityTestCGImage()))
        let task = Task {
            await cache.save(data, for: key)
        }

        task.cancel()
        await task.value

        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }
}
