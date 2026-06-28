import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeExtractJPGTestFile(_ name: String) -> FileItem {
    FileItem(
        url: URL(fileURLWithPath: "/tmp/source/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

@MainActor
struct ExtractJPGsSelectionTests {
    @Test
    func `multi-selected thumbnails win over single selected image`() {
        let viewModel = RawCullViewModel()
        let first = makeExtractJPGTestFile("A.ARW")
        let second = makeExtractJPGTestFile("B.ARW")
        let third = makeExtractJPGTestFile("C.ARW")

        viewModel.files = [first, second, third]
        viewModel.filteredFiles = [third, second, first]
        viewModel.selectedFileID = first.id
        viewModel.selectedFileIDs = [second.id, third.id]

        #expect(viewModel.selectedFilesForJPGExtraction.map(\.name) == ["C.ARW", "B.ARW"])
    }

    @Test
    func `single selected image is used when there is no thumbnail multi-selection`() {
        let viewModel = RawCullViewModel()
        let first = makeExtractJPGTestFile("A.ARW")
        let second = makeExtractJPGTestFile("B.ARW")

        viewModel.files = [first, second]
        viewModel.filteredFiles = [second, first]
        viewModel.selectedFileID = first.id
        viewModel.selectedFileIDs = []

        #expect(viewModel.selectedFilesForJPGExtraction.map(\.name) == ["A.ARW"])
    }

    @Test
    func `no selected image blocks extraction`() {
        let viewModel = RawCullViewModel()
        let destination = ARWSourceCatalog(
            name: "Destination",
            url: URL(fileURLWithPath: "/tmp/destination", isDirectory: true),
        )

        viewModel.files = [makeExtractJPGTestFile("A.ARW")]
        viewModel.filteredFiles = viewModel.files
        viewModel.startSelectedJPGExtraction(destination: destination, exportMode: .embeddedJPG)

        #expect(viewModel.selectedFilesForJPGExtraction.isEmpty)
        #expect(viewModel.currentExtractAndSaveJPGsActor == nil)
        #expect(!viewModel.creatingthumbnails)
    }
}

struct ExtractJPGsOutputURLTests {
    @Test
    func `embedded export writes natural jpg name in destination catalog`() {
        let source = URL(fileURLWithPath: "/tmp/source/Alpha.ARW")
        let destination = URL(fileURLWithPath: "/tmp/destination", isDirectory: true)

        let outputURL = SaveJPGImage.outputURL(
            for: source,
            in: destination,
            exportMode: .embeddedJPG,
        )

        #expect(outputURL == destination.appendingPathComponent("Alpha.jpg"))
    }

    @Test
    func `demosaiced export writes suffixed jpg name in destination catalog`() {
        let source = URL(fileURLWithPath: "/tmp/source/Alpha.ARW")
        let destination = URL(fileURLWithPath: "/tmp/destination", isDirectory: true)

        let outputURL = SaveJPGImage.outputURL(
            for: source,
            in: destination,
            exportMode: .demosaicedRAW,
        )

        #expect(outputURL == destination.appendingPathComponent("Alpha_demosaic.jpg"))
    }
}
