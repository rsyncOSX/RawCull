import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

@MainActor
struct SavedFilesJSONTests {
    @Test
    func `reader distinguishes missing and corrupt stores`() throws {
        let missingURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: missingURL)
        defer { try? FileManager.default.removeItem(at: root) }

        guard case let .missing(readURL) = ReadSavedFilesJSON(savedFilesURL: missingURL).read() else {
            Issue.record("Expected a missing-store result")
            return
        }
        #expect(readURL == missingURL)

        try FileManager.default.createDirectory(
            at: missingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("{not-json".utf8).write(to: missingURL)

        guard case let .failed(failure) = ReadSavedFilesJSON(savedFilesURL: missingURL).read() else {
            Issue.record("Expected a corrupt-store failure")
            return
        }
        #expect(failure.url == missingURL)
        #expect(try Data(contentsOf: missingURL) == Data("{not-json".utf8))
    }

    @Test
    func `second write preserves previous store as backup`() async throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        var saved = SavedFiles(
            catalog: catalog,
            dateStart: "now",
            filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 2),
        )
        try await WriteSavedFilesJSON.write([saved], to: fileURL)
        saved.filerecords?[0].rating = 5

        try await WriteSavedFilesJSON.write([saved], to: fileURL)

        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("savedfiles.backup.json")
        let backup = try JSONDecoder().decode([DecodeSavedFiles].self, from: Data(contentsOf: backupURL))
        #expect(backup.first?.filerecords?.first?.rating == 2)
    }

    @Test
    func `write creates Application Support directory and saved files JSON`() async throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 4),
            ),
        ]

        try await WriteSavedFilesJSON.write(savedFiles, to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: data)
        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 4)
    }

    @Test
    func `older saved files JSON decodes`() throws {
        let json = """
        [{
          "catalog": "file:///tmp/catalog/",
          "dateStart": "19 May 2026 12:00",
          "filerecords": [{
            "fileName": "one.ARW",
            "rating": 3
          }]
        }]
        """
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: Data(json.utf8))
        let saved = try #require(decoded.first.map(SavedFiles.init))

        #expect(saved.catalog == URL(string: "file:///tmp/catalog/"))
        #expect(saved.filerecords?.first?.fileName == "one.ARW")
    }

    @Test
    func `read loads saved files from Application Support URL`() throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "two.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            ),
        ]
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let data = try JSONEncoder().encode(savedFiles)
        try data.write(to: fileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: fileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "two.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    @Test
    func `read ignores old Documents file when Application Support file exists`() throws {
        let newFileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: newFileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFileURL = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("savedfiles.json")
        let newCatalog = URL(fileURLWithPath: "/tmp/new-catalog-\(UUID().uuidString)")
        let oldCatalog = URL(fileURLWithPath: "/tmp/old-catalog-\(UUID().uuidString)")
        let newSavedFiles = [
            SavedFiles(
                catalog: newCatalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "new.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            ),
        ]
        let oldSavedFiles = [
            SavedFiles(
                catalog: oldCatalog,
                dateStart: "18 May 2026 12:00",
                filerecord: FileRecord(fileName: "old.ARW", dateTagged: nil, dateCopied: nil, rating: 1),
            ),
        ]
        try FileManager.default.createDirectory(
            at: newFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: oldFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode(newSavedFiles).write(to: newFileURL)
        try JSONEncoder().encode(oldSavedFiles).write(to: oldFileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: newFileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == newCatalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "new.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    private func savedFilesTestRoot(for fileURL: URL) -> URL {
        fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
