//
//  ItemizedOutputTests.swift
//  RawCullSAM3Tests
//

@testable import RawCull
import Testing

struct ItemizedOutputTests {
    @Test
    func `Classifies rsync itemized output`() throws {
        let added = try #require(ItemizedOutputRecord(">f+++++++++ new-file.ARW"))
        let directory = try #require(ItemizedOutputRecord("cd+++++++++ new-folder/"))
        let updated = try #require(ItemizedOutputRecord(">f.st...... changed.ARW"))
        let metadata = try #require(ItemizedOutputRecord(".d..t...... folder/"))
        let deleted = try #require(ItemizedOutputRecord("*deleting removed.ARW"))

        #expect(added.kind == .added)
        #expect(directory.kind == .added)
        #expect(updated.kind == .updated)
        #expect(metadata.kind == .metadata)
        #expect(deleted.kind == .deleted)
        #expect(deleted.path == "removed.ARW")
    }

    @Test
    func `Supports openrsync itemized output`() throws {
        let added = try #require(ItemizedOutputRecord(">f+++++++ file.ARW"))
        let metadata = try #require(ItemizedOutputRecord(".d..t.... folder/"))

        #expect(added.kind == .added)
        #expect(metadata.kind == .metadata)
    }

    @Test
    func `Ignores empty and summary lines`() {
        #expect(ItemizedOutputRecord("") == nil)
        #expect(ItemizedOutputRecord("Number of files: 10 (reg: 8, dir: 2)") == nil)
        #expect(ItemizedOutputRecord("sent 1,234 bytes  received 56 bytes  2,580.00 bytes/sec") == nil)
        #expect(ItemizedOutputRecord("total size is 1,048,576  speedup is 812.85") == nil)
    }
}
