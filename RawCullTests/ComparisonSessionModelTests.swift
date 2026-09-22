import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeComparisonSessionFile(_ name: String) -> FileItem {
    FileItem(
        id: UUID(),
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

@MainActor
private final class ComparisonSessionSelectionSpy: ComparisonSessionSelection {
    var selectedFileID: FileItem.ID?
}

@MainActor
private final class ComparisonSessionImageServiceSpy: ComparisonSessionImageServing {
    var loadedFiles: [FileItem] = []
    var loadedSourceFlags: [FileItem.ID: Bool] = [:]
    var reloadedFile: FileItem?
    var reloadedSourceFlags: [FileItem.ID: Bool] = [:]
    var regeneratedFiles: [FileItem] = []
    var cancelCount = 0

    func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool],
    ) {
        loadedFiles = files
        loadedSourceFlags = sourceFlags
        return (
            Dictionary(uniqueKeysWithValues: files.map {
                ($0.id, ComparisonImageState(id: $0.id, isLoading: false))
            }),
            sourceFlags,
        )
    }

    func reloadImage(
        for file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
    ) async -> ComparisonImageState {
        reloadedFile = file
        reloadedSourceFlags = sourceFlags
        return ComparisonImageState(id: file.id, isLoading: false)
    }

    func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
    ) async -> [FileItem.ID: ComparisonImageState] {
        regeneratedFiles = files
        return states
    }

    func cancel() {
        cancelCount += 1
    }
}

@MainActor
@Suite("ComparisonSessionModel")
struct ComparisonSessionModelTests {
    @Test
    func `lifecycle activates and cancels injected image services`() {
        let imageService = ComparisonSessionImageServiceSpy()
        let model = makeModel(imageService: imageService)

        #expect(!model.isActive)

        model.activate()
        #expect(model.isActive)

        model.cancel()
        #expect(!model.isActive)
        #expect(imageService.cancelCount == 1)
    }

    @Test
    func `selection intents use the injected narrow selection boundary`() {
        let first = makeComparisonSessionFile("first.ARW")
        let second = makeComparisonSessionFile("second.ARW")
        let selection = ComparisonSessionSelectionSpy()
        let model = makeModel(selection: selection)

        model.select(first.id)
        #expect(selection.selectedFileID == first.id)

        model.moveSelection(.right, in: [first, second])
        #expect(selection.selectedFileID == second.id)

        model.moveSelection(.right, in: [first, second])
        #expect(selection.selectedFileID == second.id)
    }

    @Test
    func `image intents route through the injected image service`() async {
        let file = makeComparisonSessionFile("image.ARW")
        let sourceFlags = [file.id: true]
        let imageService = ComparisonSessionImageServiceSpy()
        let model = makeModel(imageService: imageService)

        let loaded = await model.loadImages(files: [file], sourceFlags: sourceFlags)
        let reloaded = await model.reload(file, sourceFlags: sourceFlags)
        let regenerated = await model.regenerateFocusMasks(
            files: [file],
            states: loaded.states,
        )

        #expect(imageService.loadedFiles.map(\.id) == [file.id])
        #expect(imageService.loadedSourceFlags == sourceFlags)
        #expect(imageService.reloadedFile?.id == file.id)
        #expect(imageService.reloadedSourceFlags == sourceFlags)
        #expect(imageService.regeneratedFiles.map(\.id) == [file.id])
        #expect(reloaded.id == file.id)
        #expect(regenerated[file.id]?.id == file.id)
    }

    private func makeModel(
        imageService: ComparisonSessionImageServiceSpy = ComparisonSessionImageServiceSpy(),
        selection: ComparisonSessionSelectionSpy = ComparisonSessionSelectionSpy(),
    ) -> ComparisonSessionModel {
        ComparisonSessionModel(imageService: imageService, selection: selection)
    }
}
