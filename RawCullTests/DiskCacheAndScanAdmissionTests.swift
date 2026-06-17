import AppKit
import Foundation
import ImageIO
@testable import RawCull
import Testing
import UniformTypeIdentifiers

private func makeCacheTestRoot(_ name: String = #function) throws -> URL {
    let safeName = name
        .replacingOccurrences(of: "`", with: "")
        .replacingOccurrences(of: " ", with: "-")
        .replacingOccurrences(of: "()", with: "")
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("RawCullVerifyTests", isDirectory: true)
        .appendingPathComponent("\(safeName)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func makeCacheTestCGImage(width: Int = 32, height: Int = 24, color: NSColor = .red) throws -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(color.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return try #require(context.makeImage())
}

private func makeOrientedJPEGData(width: Int, height: Int, orientation: Int) throws -> Data {
    let image = try makeCacheTestCGImage(width: width, height: height)
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(
        data,
        UTType.jpeg.identifier as CFString,
        1,
        nil,
    ))
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: orientation
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

private func writeOrientedJPEG(
    root: URL,
    name: String,
    width: Int,
    height: Int,
    orientation: Int,
) throws -> (URL, Data) {
    let data = try makeOrientedJPEGData(width: width, height: height, orientation: orientation)
    let url = root.appendingPathComponent(name)
    try data.write(to: url)
    return (url, data)
}

struct OrientationNormalizedImageLoaderTests {
    @Test
    func `URL decode applies right orientation to portrait dimensions`() throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (url, _) = try writeOrientedJPEG(
            root: root,
            name: "right.jpg",
            width: 80,
            height: 40,
            orientation: 6,
        )

        let image = try #require(OrientationNormalizedImageLoader.loadCGImage(from: url))

        #expect(image.width == 40)
        #expect(image.height == 80)
    }

    @Test
    func `URL decode keeps up orientation dimensions unchanged`() throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let (url, _) = try writeOrientedJPEG(
            root: root,
            name: "up.jpg",
            width: 80,
            height: 40,
            orientation: 1,
        )

        let image = try #require(OrientationNormalizedImageLoader.loadCGImage(from: url))

        #expect(image.width == 80)
        #expect(image.height == 40)
    }

    @Test
    func `data decode applies right orientation to portrait dimensions`() throws {
        let data = try makeOrientedJPEGData(width: 80, height: 40, orientation: 6)

        let image = try #require(OrientationNormalizedImageLoader.loadCGImage(from: data))

        #expect(image.width == 40)
        #expect(image.height == 80)
    }
}

struct DiskCacheManagerTests {
    @Test
    func `save and load thumbnail JPEG from isolated disk cache`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let cgImage = try makeCacheTestCGImage(width: 40, height: 30)
        let data = try #require(DiskCacheManager.jpegData(from: cgImage))

        await cache.save(data, for: source)
        let loaded = await cache.load(for: source)
        let size = await cache.getDiskCacheSize()

        #expect(loaded != nil)
        #expect(Int(loaded?.size.width ?? 0) == 40)
        #expect(Int(loaded?.size.height ?? 0) == 30)
        #expect(size > 0)
    }

    @Test
    func `saving same source overwrites existing thumbnail cache entry`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let first = try #require(DiskCacheManager.jpegData(from: makeCacheTestCGImage(width: 20, height: 20, color: .red)))
        let second = try #require(DiskCacheManager.jpegData(from: makeCacheTestCGImage(width: 60, height: 40, color: .blue)))

        await cache.save(first, for: source)
        await cache.save(second, for: source)
        let loaded = await cache.load(for: source)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)

        #expect(entries.count == 1)
        #expect(Int(loaded?.size.width ?? 0) == 60)
        #expect(Int(loaded?.size.height ?? 0) == 40)
    }

    @Test
    func `pruneCache removes old thumbnail files`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = DiskCacheManager(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let data = try #require(DiskCacheManager.jpegData(from: makeCacheTestCGImage()))

        await cache.save(data, for: source)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let cachedFile = try #require(files.first)
        let oldDate = Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cachedFile.path)

        await cache.pruneCache(maxAgeInDays: 1)

        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }
}

struct FullSizeJPGDiskCacheTests {
    @Test
    func `save contains and load full size JPEG from isolated disk cache`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FullSizeJPGDiskCache(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let cgImage = try makeCacheTestCGImage(width: 64, height: 48)
        let data = try #require(FullSizeJPGDiskCache.jpegData(from: cgImage))

        #expect(await cache.contains(for: source) == false)
        await cache.save(data, for: source)

        let loaded = await cache.load(for: source)
        #expect(await cache.contains(for: source))
        #expect(loaded?.width == 64)
        #expect(loaded?.height == 48)
        #expect(await cache.getDiskCacheSize() > 0)
    }

    @Test
    func `load full size JPEG applies cached orientation metadata`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FullSizeJPGDiskCache(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let data = try makeOrientedJPEGData(width: 80, height: 40, orientation: 6)

        await cache.save(data, for: source)
        let loaded = try #require(await cache.load(for: source))

        #expect(loaded.width == 40)
        #expect(loaded.height == 80)
    }

    @Test
    func `saving same source overwrites existing full size cache entry`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FullSizeJPGDiskCache(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let first = try #require(FullSizeJPGDiskCache.jpegData(from: makeCacheTestCGImage(width: 20, height: 20)))
        let second = try #require(FullSizeJPGDiskCache.jpegData(from: makeCacheTestCGImage(width: 80, height: 50)))

        await cache.save(first, for: source)
        await cache.save(second, for: source)
        let loaded = await cache.load(for: source)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)

        #expect(entries.count == 1)
        #expect(loaded?.width == 80)
        #expect(loaded?.height == 50)
    }

    @Test
    func `embedded and developed JPEGs use separate cache entries`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FullSizeJPGDiskCache(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let embedded = try #require(FullSizeJPGDiskCache.jpegData(from: makeCacheTestCGImage(width: 40, height: 30)))
        let developed = try #require(FullSizeJPGDiskCache.jpegData(from: makeCacheTestCGImage(width: 80, height: 60)))

        await cache.save(embedded, for: source)
        await cache.save(developed, for: source, variant: .developedRAW)

        let defaultLoaded = await cache.load(for: source)
        let developedLoaded = await cache.load(for: source, variant: .developedRAW)
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)

        #expect(entries.count == 2)
        #expect(defaultLoaded?.width == 40)
        #expect(defaultLoaded?.height == 30)
        #expect(developedLoaded?.width == 80)
        #expect(developedLoaded?.height == 60)
    }

    @Test
    func `pruneCache removes old full size JPEG files`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = FullSizeJPGDiskCache(cacheDirectory: root)
        let source = URL(fileURLWithPath: "/tmp/source-\(UUID().uuidString).arw")
        let data = try #require(FullSizeJPGDiskCache.jpegData(from: makeCacheTestCGImage()))

        await cache.save(data, for: source)
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let cachedFile = try #require(files.first)
        let oldDate = Date(timeIntervalSinceNow: -3 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: cachedFile.path)

        await cache.pruneCache(maxAgeInDays: 1)

        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).isEmpty)
    }
}

struct ScanAndCreateThumbnailsCacheAdmissionTests {
    @Test
    func `preload from disk cache admits only to grid cache not memory cache`() async throws {
        let root = try makeCacheTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("Catalog", isDirectory: true)
        let diskDirectory = root.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)

        let rawURL = catalog.appendingPathComponent("cached.ARW")
        try Data().write(to: rawURL)

        let diskCache = DiskCacheManager(cacheDirectory: diskDirectory)
        let jpegData = try #require(DiskCacheManager.jpegData(from: makeCacheTestCGImage(width: 90, height: 60)))
        await diskCache.save(jpegData, for: rawURL)

        SharedMemoryCache.shared.removeAllObjects()
        SharedMemoryCache.shared.removeAllGridObjects()
        let provider = ScanAndCreateThumbnails(diskCache: diskCache)

        let processed = await provider.preloadCatalog(at: catalog, targetSize: 256)

        #expect(processed == 1)
        #expect(SharedMemoryCache.shared.object(forKey: rawURL as NSURL) == nil)
        #expect(SharedMemoryCache.shared.gridObject(forKey: rawURL as NSURL) != nil)
    }
}
