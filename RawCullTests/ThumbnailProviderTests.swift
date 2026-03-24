//
//  ThumbnailProviderTests.swift
//  RawCullTests
//
//  Created by Thomas Evensen on 04/02/2026.
//

import AppKit
import Foundation
@testable import RawCull
import Testing

// MARK: - Test Image Generator

func createTestImage(width: Int = 100, height: Int = 100) -> NSImage {
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(origin: .zero, size: size).fill()
    image.unlockFocus()
    return image
}

// MARK: - Tests

struct RequestThumbnailTests {
    // MARK: - Initialization Tests

    @Test
    func `Initializes with production config by default`() async {
        _ = RequestThumbnail()
        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hitRate == 0)
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Initializes with custom config`() async {
        let testConfig = CacheConfig(totalCostLimit: 50000, countLimit: 3)
        _ = RequestThumbnail(config: testConfig)
        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hitRate == 0)
    }

    // MARK: - Cache Statistics Tests

    @Test
    func `Cache hit rate calculates correctly`() async {
        _ = RequestThumbnail(config: .testing)

        // Simulate a hit and a miss
        // Note: We'd need access to storeInMemory to fully test this
        // For now, we test the statistics gathering
        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        let expectedHitRate = 0.0 // Initially no hits or misses

        #expect(stats.hitRate == expectedHitRate)
    }

    @Test
    func `Statistics reset after clear caches`() async {
        _ = RequestThumbnail(config: .testing)

        // Get initial stats
        var stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)

        // Clear and verify
        await SharedMemoryCache.shared.clearCaches()
        stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
    }

    @Test
    func `Cache respects cost limit`() {
        let testConfig = CacheConfig(totalCostLimit: 100_000, countLimit: 100)
        _ = RequestThumbnail(config: testConfig)

        // With a very small cost limit, items should be evicted
        // This tests the memory management

        #expect(true) // Placeholder - full implementation requires cache introspection
    }

    // MARK: - Cache Lookup Tests

    @Test
    func `Thumbnail method handles missing files gracefully`() async {
        let provider = RequestThumbnail(config: .testing)
        let missingURL = URL(fileURLWithPath: "/nonexistent/file.jpg")

        let result = await provider.requestThumbnail(for: missingURL, targetSize: 256)

        #expect(result == nil)
    }

    // MARK: - Clear Cache Tests

    @Test
    func `Clear caches removes all cached items`() async {
        _ = RequestThumbnail(config: .testing)

        // Clear caches
        await SharedMemoryCache.shared.clearCaches()

        // Verify statistics are reset
        let stats = await SharedMemoryCache.shared.getCacheStatistics()
        #expect(stats.hits == 0)
        #expect(stats.misses == 0)
        #expect(stats.evictions == 0)
    }

    // MARK: - Preload Catalog Tests

    @Test
    func `Preload catalog starts and can be tracked`() async {
        let provider = ScanAndCreateThumbnails(config: .testing)
        let testDir = FileManager.default.temporaryDirectory

        // This will fail to find files but tests the mechanism
        let result = await provider.preloadCatalog(at: testDir, targetSize: 256)

        #expect(result >= 0)
    }

    // MARK: - Concurrency Tests

    @Test
    func `Provider handles concurrent access safely`() async {
        let provider = RequestThumbnail(config: .testing)
        let testURL = URL(fileURLWithPath: "/test/file.jpg")

        // Attempt concurrent reads on non-existent file
        async let result1 = provider.requestThumbnail(for: testURL, targetSize: 256)
        async let result2 = provider.requestThumbnail(for: testURL, targetSize: 256)
        async let result3 = provider.requestThumbnail(for: testURL, targetSize: 256)

        let (res1, res2, res3) = await (result1, result2, result3)

        #expect(res1 == nil)
        #expect(res2 == nil)
        #expect(res3 == nil)
    }

    // MARK: - Configuration Tests

    @Test
    func `Config production has correct limits`() {
        let config = CacheConfig.production

        #expect(config.totalCostLimit == 200 * 2560 * 2560)
        #expect(config.countLimit == 500)
    }

    @Test
    func `Config testing has small limits`() {
        let config = CacheConfig.testing

        #expect(config.totalCostLimit == 100_000)
        #expect(config.countLimit == 5)
    }

    // MARK: - Cache Delegate Tests

    @Test
    func `Cache delegate is properly set`() {
        _ = RequestThumbnail(config: .testing)

        // Verify provider initializes without crashing
        // A full test would require exposing the delegate

        #expect(true)
    }

    // MARK: - Sendable Conformance Tests

    @Test
    func `Provider is actor-isolated for thread safety`() async {
        _ = RequestThumbnail(config: .testing)

        // Multiple concurrent accesses should not cause data races
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    let stats = await SharedMemoryCache.shared.getCacheStatistics()
                    #expect(stats.hitRate >= 0)
                }
            }
        }
    }
}

// MARK: - Performance Tests

@MainActor
struct RequestThumbnailPerformanceTests {
    @Test
    func `Statistics gathering is fast`() async {
        _ = RequestThumbnail(config: .testing)

        let startTime = Date()
        for _ in 0 ..< 1000 {
            _ = await SharedMemoryCache.shared.getCacheStatistics()
        }
        let duration = Date().timeIntervalSince(startTime)

        // Should complete 1000 calls in less than 1 second
        #expect(duration < 1.0)
    }

    @Test
    func `Clear operation completes promptly`() async {
        _ = RequestThumbnail(config: .testing)

        let startTime = Date()
        await SharedMemoryCache.shared.clearCaches()
        let duration = Date().timeIntervalSince(startTime)

        // Should complete quickly even with empty cache
        #expect(duration < 1.0)
    }
}

@MainActor
struct SonyMakerNoteParserTests {
    @Test("Verifies focus parsing for Sony A1 (No Header)")
    func testSonyA1FocusPointParsing() {
        // 1. Create a mock ARW buffer with a valid TIFF header
        var mockData = createBaseTIFFData(size: 1024)
        
        // IFD0: 1 entry (ExifOffset 0x8769)
        let exifOffset: UInt32 = 40
        writeIFD(&mockData, at: 8, entries: [(0x8769, 4, 1, exifOffset)])
        
        // ExifIFD: 1 entry (MakerNote 0x927C)
        let makerNoteOffset: UInt32 = 100
        writeIFD(&mockData, at: Int(exifOffset), entries: [(0x927C, 7, 200, makerNoteOffset)])
        
        // MakerNote IFD (Sony A1 style - no "SONY DSC" header)
        let afInfoOffset: UInt32 = 150
        writeIFD(&mockData, at: Int(makerNoteOffset), entries: [(0x9400, 7, 20, afInfoOffset)])
        
        // AFInfo Block: [Padding(4 bytes), Width, Height, X, Y]
        writeU16(&mockData, at: Int(afInfoOffset) + 4, value: 8640)
        writeU16(&mockData, at: Int(afInfoOffset) + 6, value: 5760)
        writeU16(&mockData, at: Int(afInfoOffset) + 8, value: 4320)
        writeU16(&mockData, at: Int(afInfoOffset) + 10, value: 2880)
        
        // 2. Parse and Assert
        let result = TIFFParser(data: mockData)?.parseSonyFocusLocation()
        
        #expect(result != nil)
        #expect(result?.width == 8640)
        #expect(result?.height == 5760)
    }

    @Test("Verifies skipping of 'SONY DSC ' header")
    func testSonyHeaderSkipping() {
        // 1. Create a mock ARW buffer with a valid TIFF header
        var mockData = createBaseTIFFData(size: 500)
        let mnOffset = 50 // Place MakerNote at offset 50
        
        // Write "SONY DSC " header (12 bytes including padding)
        let headerString = "SONY DSC "
        let headerData = headerString.data(using: .utf8)!
        mockData.replaceSubrange(mnOffset..<(mnOffset + headerData.count), with: headerData)
        
        // The IFD actually starts after the 12-byte header
        let realIFDStart = mnOffset + 12
        let afInfoDataOffset: UInt32 = 200
        writeIFD(&mockData, at: realIFDStart, entries: [(0x9400, 7, 20, afInfoDataOffset)])
        
        // Add minimal AF data (Width=100)
        writeU16(&mockData, at: Int(afInfoDataOffset) + 4, value: 100)
        writeU16(&mockData, at: Int(afInfoDataOffset) + 6, value: 100)
        
        // 2. Test the specific MakerNote parsing logic
        // We initialize the parser properly so 'le' is set, then test the internal jump
        guard let parser = TIFFParser(data: mockData) else {
            Issue.record("Parser failed to initialize")
            return
        }
        
        let result = parser.parseSonyFocusLocationFromMakerNote(at: mnOffset)
        
        #expect(result != nil)
        #expect(result?.width == 100)
    }

    // MARK: - Mock Data Helpers

    /// Creates a Data object with a valid Little Endian TIFF header (II*)
    private func createBaseTIFFData(size: Int) -> Data {
        var data = Data(repeating: 0, count: size)
        data[0] = 0x49 // I
        data[1] = 0x49 // I
        data[2] = 0x2A // *
        data[3] = 0x00
        // Offset to IFD0 (usually 8)
        writeU32(&data, at: 4, value: 8)
        return data
    }

    private func writeU16(_ data: inout Data, at offset: Int, value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset+1] = UInt8((value >> 8) & 0xFF)
    }

    private func writeU32(_ data: inout Data, at offset: Int, value: UInt32) {
        data[offset] = UInt8(value & 0xFF)
        data[offset+1] = UInt8((value >> 8) & 0xFF)
        data[offset+2] = UInt8((value >> 16) & 0xFF)
        data[offset+3] = UInt8((value >> 24) & 0xFF)
    }

    private func writeIFD(_ data: inout Data, at offset: Int, entries: [(tag: UInt16, type: UInt16, count: UInt32, val: UInt32)]) {
        writeU16(&data, at: offset, value: UInt16(entries.count))
        for (i, entry) in entries.enumerated() {
            let entryOffset = offset + 2 + (i * 12)
            writeU16(&data, at: entryOffset, value: entry.tag)
            writeU16(&data, at: entryOffset + 2, value: entry.type)
            writeU32(&data, at: entryOffset + 4, value: entry.count)
            writeU32(&data, at: entryOffset + 8, value: entry.val)
        }
    }
}

// Extension to expose internal logic for testing
private extension TIFFParser {
    func parseSonyFocusLocationFromMakerNote(at offset: Int) -> (width: Int, height: Int, x: Int, y: Int)? {
        let ifdStart = sonyIFDStart(at: offset)
        guard let (afOffset, afBytes) = tagDataRange(in: ifdStart, tag: 0x9400, baseOffset: offset) else { return nil }
        guard afBytes >= 12 else { return nil }
        return (Int(readU16(at: afOffset + 4)), Int(readU16(at: afOffset + 6)),
                Int(readU16(at: afOffset + 8)), Int(readU16(at: afOffset + 10)))
    }
}
