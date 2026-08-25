import CoreGraphics
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

private nonisolated struct MissingEmbeddedPreviewLoader: FullSizePreviewLoading {
    func loadEmbeddedPreview(for _: URL) async -> CGImage? {
        nil
    }
}

@MainActor
private final class JPGExportProgressRecorder {
    var completed: [Int] = []
    var total = 0
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

    @Test
    func `denied destination access blocks extraction and presents error`() {
        let viewModel = RawCullViewModel()
        let file = makeExtractJPGTestFile("A.ARW")
        let destination = ARWSourceCatalog(
            name: "Destination",
            url: URL(fileURLWithPath: "/tmp/destination", isDirectory: true),
        )
        viewModel.files = [file]
        viewModel.filteredFiles = [file]
        viewModel.selectedFileID = file.id
        viewModel.startSecurityScopedResource = { _ in false }

        viewModel.startSelectedJPGExtraction(destination: destination, exportMode: .embeddedJPG)

        #expect(viewModel.currentExtractAndSaveJPGsActor == nil)
        #expect(!viewModel.creatingthumbnails)
        #expect(viewModel.operationFailurePresentation?.title == "Export Not Started")
    }

    @Test
    func `present extract jpgs defaults destination to selected source only when empty`() {
        let viewModel = RawCullViewModel()
        let source = ARWSourceCatalog(
            name: "Source",
            url: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        )

        viewModel.sources = [source]
        viewModel.selectedSource = source

        viewModel.presentExtractJPGsSheet()

        #expect(viewModel.extractJPGDestination == source)
        #expect(viewModel.activeSheet == .extractJPGs)
    }

    @Test
    func `present extract jpgs preserves destination outside source catalogs`() {
        let viewModel = RawCullViewModel()
        let source = ARWSourceCatalog(
            name: "Source",
            url: URL(fileURLWithPath: "/tmp/source", isDirectory: true),
        )
        let externalDestination = ARWSourceCatalog(
            name: "Exports",
            url: URL(fileURLWithPath: "/tmp/exports", isDirectory: true),
        )

        viewModel.sources = [source]
        viewModel.selectedSource = source
        viewModel.extractJPGDestination = externalDestination

        viewModel.presentExtractJPGsSheet()

        #expect(viewModel.extractJPGDestination == externalDestination)
        #expect(viewModel.activeSheet == .extractJPGs)
    }
}

struct ExtractJPGsOutputURLTests {
    @Test
    func `failed exports still advance completed count and report every failure`() async {
        let files = [
            makeExtractJPGTestFile("A.ARW"),
            makeExtractJPGTestFile("B.ARW")
        ]
        let recorder = JPGExportProgressRecorder()
        let actor = ExtractAndSaveJPGs(
            files: files,
            destinationCatalogURL: URL(fileURLWithPath: "/tmp/destination", isDirectory: true),
            exportMode: .embeddedJPG,
            previewLoader: MissingEmbeddedPreviewLoader(),
        )
        let handlers = await CreateFileHandlers().createFileHandlers(
            fileHandler: { recorder.completed.append($0) },
            maxfilesHandler: { recorder.total = $0 },
            estimatedTimeHandler: { _ in },
            memorypressurewarning: { _ in },
            onExtractionNeeded: {},
        )
        await actor.setFileHandlers(handlers)

        let result = await actor.extractAndSavejpgs()
        let progress = await MainActor.run { (recorder.completed, recorder.total) }

        #expect(result.succeeded == 0)
        #expect(result.failures.count == files.count)
        #expect(progress.1 == files.count)
        #expect(progress.0.contains(files.count))
    }

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

    @Test
    func `save propagates destination write failure`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCull-export-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("not a directory".utf8).write(to: root)

        var didThrow = false
        do {
            try await SaveJPGImage().save(
                Data([0xFF, 0xD8, 0xFF, 0xD9]),
                originalURL: URL(fileURLWithPath: "/tmp/source/Alpha.ARW"),
                destinationCatalogURL: root,
                exportMode: .embeddedJPG,
            )
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }
}
