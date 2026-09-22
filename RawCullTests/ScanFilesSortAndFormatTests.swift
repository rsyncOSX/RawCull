import Foundation
@testable import RawCull
import RawCullCore
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
            by: FileItemSortDescriptor(field: .name),
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
            by: FileItemSortDescriptor(field: .dateModified, direction: .descending),
            searchText: "",
        )

        #expect(fileNames(sorted) == ["recent.ARW", "middle.ARW", "old.ARW"])
    }

    @Test
    func `sortFiles sorts by date ascending`() async {
        let files = [
            makeSortTestFile(name: "recent.ARW", size: 30, date: recent),
            makeSortTestFile(name: "old.ARW", size: 10, date: old),
            makeSortTestFile(name: "middle.ARW", size: 20, date: middle)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: FileItemSortDescriptor(field: .dateModified),
            searchText: "",
        )

        #expect(fileNames(sorted) == ["old.ARW", "middle.ARW", "recent.ARW"])
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
            by: FileItemSortDescriptor(field: .size),
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
            by: FileItemSortDescriptor(field: .name),
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
            by: FileItemSortDescriptor(field: .name),
            searchText: "bird",
        )

        #expect(fileNames(sorted) == ["bird-close.ARW", "bird-wide.NEF"])
    }

    @Test(arguments: [
        FileItemSortField.name,
        .dateModified,
        .size,
    ])
    func `sortFiles supports descending order for every field`(field: FileItemSortField) async {
        let files = [
            makeSortTestFile(name: "a.ARW", size: 10, date: old),
            makeSortTestFile(name: "b.ARW", size: 20, date: middle),
            makeSortTestFile(name: "c.ARW", size: 30, date: recent)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: FileItemSortDescriptor(field: field, direction: .descending),
            searchText: "",
        )

        #expect(fileNames(sorted) == ["c.ARW", "b.ARW", "a.ARW"])
    }

    @Test
    func `sortFiles preserves input order when field values tie`() async {
        let files = [
            makeSortTestFile(name: "first.ARW", size: 10, date: old),
            makeSortTestFile(name: "second.ARW", size: 10, date: middle),
            makeSortTestFile(name: "third.ARW", size: 10, date: recent)
        ]

        let sorted = await ScanFiles.sortFiles(
            files,
            by: FileItemSortDescriptor(field: .size, direction: .descending),
            searchText: "",
        )

        #expect(fileNames(sorted) == ["first.ARW", "second.ARW", "third.ARW"])
    }

    @Test
    func `sortFiles handles empty and single-item input`() async {
        let descriptor = FileItemSortDescriptor(field: .dateModified)
        let file = makeSortTestFile(name: "only.ARW", size: 10, date: old)

        let empty = await ScanFiles.sortFiles([], by: descriptor, searchText: "")
        let single = await ScanFiles.sortFiles([file], by: descriptor, searchText: "")

        #expect(empty.isEmpty)
        #expect(fileNames(single) == ["only.ARW"])
    }
}
