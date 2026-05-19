import Foundation
@testable import RawCull
import Testing

private func makeSortTestFile(
    name: String,
    size: Int64,
    date: Date,
) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: size,
        dateModified: date,
        exifData: nil,
        afFocusNormalized: nil,
    )
}

@MainActor
private func fileNames(_ files: [FileItem]) -> [String] {
    files.map { $0.name }
}

@MainActor
struct ScanFilesSortTests {
    private let old = Date(timeIntervalSince1970: 1000)
    private let middle = Date(timeIntervalSince1970: 2000)
    private let recent = Date(timeIntervalSince1970: 3000)

    @Test
    func `sortFiles sorts by name ascending`() async {
        let files = [
            makeSortTestFile(name: "B.ARW", size: 10, date: middle),
            makeSortTestFile(name: "a.ARW", size: 20, date: old),
            makeSortTestFile(name: "C.NEF", size: 30, date: recent)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: [KeyPathComparator(\FileItem.name)],
            searchText: "",
        )

        #expect(fileNames(sorted) == ["a.ARW", "B.ARW", "C.NEF"])
    }

    @Test
    func `sortFiles sorts by date descending`() async {
        let files = [
            makeSortTestFile(name: "old.ARW", size: 10, date: old),
            makeSortTestFile(name: "recent.ARW", size: 20, date: recent),
            makeSortTestFile(name: "middle.ARW", size: 30, date: middle)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: [KeyPathComparator(\FileItem.dateModified, order: .reverse)],
            searchText: "",
        )

        #expect(fileNames(sorted) == ["recent.ARW", "middle.ARW", "old.ARW"])
    }

    @Test
    func `sortFiles sorts by size ascending`() async {
        let files = [
            makeSortTestFile(name: "large.ARW", size: 300, date: old),
            makeSortTestFile(name: "small.ARW", size: 100, date: middle),
            makeSortTestFile(name: "medium.ARW", size: 200, date: recent)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: [KeyPathComparator(\FileItem.size)],
            searchText: "",
        )

        #expect(fileNames(sorted) == ["small.ARW", "medium.ARW", "large.ARW"])
    }

    @Test
    func `sortFiles filters search text case insensitively after sorting`() async {
        let files = [
            makeSortTestFile(name: "zebra.NEF", size: 30, date: old),
            makeSortTestFile(name: "Alpha.ARW", size: 10, date: recent),
            makeSortTestFile(name: "beta.arw", size: 20, date: middle)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: [KeyPathComparator(\FileItem.name)],
            searchText: "ARW",
        )

        #expect(fileNames(sorted) == ["Alpha.ARW", "beta.arw"])
    }

    @Test
    func `sortFiles can search by stem fragment`() async {
        let files = [
            makeSortTestFile(name: "bird-close.ARW", size: 10, date: old),
            makeSortTestFile(name: "landscape.NEF", size: 20, date: middle),
            makeSortTestFile(name: "bird-wide.NEF", size: 30, date: recent)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: [KeyPathComparator(\FileItem.name)],
            searchText: "bird",
        )

        #expect(fileNames(sorted) == ["bird-close.ARW", "bird-wide.NEF"])
    }
}

struct RawFormatRegistryTests {
    @Test
    func `format resolves supported extensions case insensitively`() {
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image.arw")) is SonyRawFormat.Type)
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image.ARW")) is SonyRawFormat.Type)
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image.nef")) is NikonRawFormat.Type)
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image.NEF")) is NikonRawFormat.Type)
    }

    @Test
    func `format rejects unsupported extensions`() {
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image.jpg")) == nil)
        #expect(RawFormatRegistry.format(for: URL(fileURLWithPath: "/tmp/image")) == nil)
    }

    @Test
    func `allExtensions is union of registered raw formats`() {
        #expect(RawFormatRegistry.allExtensions == ["arw", "nef"])
    }
}
