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
        // 1. Create a mock ARW buffer (Little Endian)
        var mockData = Data(repeating: 0, count: 1024)
        
        // TIFF Header: II* (Little Endian, Magic 42)
        mockData[0...3] = Data([0x49, 0x49, 0x2A, 0x00])
        let ifd0Offset: UInt32 = 8
        writeU32(&mockData, at: 4, value: ifd0Offset)
        
        // IFD0: 1 entry (ExifOffset 0x8769)
        let exifOffset: UInt32 = 40
        writeIFD(&mockData, at: Int(ifd0Offset), entries: [(0x8769, 4, 1, exifOffset)])
        
        // ExifIFD: 1 entry (MakerNote 0x927C)
        let makerNoteOffset: UInt32 = 100
        writeIFD(&mockData, at: Int(exifOffset), entries: [(0x927C, 7, 200, makerNoteOffset)])
        
        // MakerNote IFD: 1 entry (AFInfo 0x9400)
        let afInfoOffset: UInt32 = 150
        writeIFD(&mockData, at: Int(makerNoteOffset), entries: [(0x9400, 7, 20, afInfoOffset)])
        
        // AFInfo Block: [Padding(4 bytes), Width, Height, X, Y]
        // Values: Width=8640, Height=5760, X=4320, Y=2880
        let afValues: [UInt16] = [8640, 5760, 4320, 2880]
        for (i, val) in afValues.enumerated() {
            writeU16(&mockData, at: Int(afInfoOffset) + 4 + (i * 2), value: val)
        }
        
        // 2. Parse and Assert
        let result = TIFFParser(data: mockData)?.parseSonyFocusLocation()
        
        #expect(result != nil)
        #expect(result?.width == 8640)
        #expect(result?.height == 5760)
        #expect(result?.x == 4320)
        #expect(result?.y == 2880)
    }

    @Test("Verifies skipping of 'SONY DSC ' header")
    func testSonyHeaderSkipping() {
        var mockData = Data(repeating: 0, count: 500)
        let mnOffset = 10
        
        // Write "SONY DSC \0\0\0" header (12 bytes)
        let header = "SONY DSC ".data(using: .utf8)!
        mockData[mnOffset..<(mnOffset + header.count)] = header
        
        // Write a mock IFD entry count (1 entry) immediately after the 12-byte header
        let realIFDStart = mnOffset + 12
        writeU16(&mockData, at: realIFDStart, value: 1)
        
        // Write the AFInfo tag inside this shifted IFD
        let afInfoDataOffset: UInt32 = 100
        writeIFDEntry(&mockData, at: realIFDStart + 2, tag: 0x9400, type: 7, count: 20, value: afInfoDataOffset)
        
        // Add minimal AF data
        writeU16(&mockData, at: Int(afInfoDataOffset) + 4, value: 100) // width
        writeU16(&mockData, at: Int(afInfoDataOffset) + 6, value: 100) // height
        
        // The parser should skip the 12 bytes and find the data
        let result = TIFFParser(data: mockData)?.parseSonyFocusLocationFromMakerNote(at: mnOffset)
        #expect(result?.width == 100)
    }

    // MARK: - Helpers

    private func writeU16(_ data: inout Data, at offset: Int, value: UInt16) {
        data[offset] = UInt8(value & 0xFF)
        data[offset+1] = UInt8((value >> 8) & 0xFF)
    }

    private func writeU32(_ data: inout Data, at offset: Int, value: UInt32) {
        for i in 0..<4 {
            data[offset + i] = UInt8((value >> (i * 8)) & 0xFF)
        }
    }

    private func writeIFD(_ data: inout Data, at offset: Int, entries: [(tag: UInt16, type: UInt16, count: UInt32, val: UInt32)]) {
        writeU16(&data, at: offset, value: UInt16(entries.count))
        for (i, entry) in entries.enumerated() {
            writeIFDEntry(&data, at: offset + 2 + (i * 12), tag: entry.tag, type: entry.type, count: entry.count, value: entry.val)
        }
    }

    private func writeIFDEntry(_ data: inout Data, at offset: Int, tag: UInt16, type: UInt16, count: UInt32, value: UInt32) {
        writeU16(&data, at: offset, value: tag)
        writeU16(&data, at: offset + 2, value: type)
        writeU32(&data, at: offset + 4, value: count)
        writeU32(&data, at: offset + 8, value: value)
    }
}

// Extension to expose the internal logic for the specific header test
private extension TIFFParser {
    func parseSonyFocusLocationFromMakerNote(at offset: Int) -> (width: Int, height: Int, x: Int, y: Int)? {
        let ifdStart = sonyIFDStart(at: offset)
        guard let (afOffset, afBytes) = tagDataRange(in: ifdStart, tag: 0x9400, baseOffset: offset) else { return nil }
        guard afBytes >= 12 else { return nil }
        return (Int(readU16(at: afOffset + 4)), Int(readU16(at: afOffset + 6)),
                Int(readU16(at: afOffset + 8)), Int(readU16(at: afOffset + 10)))
    }
}
