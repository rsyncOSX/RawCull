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

private func makeComparisonSessionBurstResult(
    fileIDs: [FileItem.ID],
    recommendedFileID: FileItem.ID,
    secondBestFileID: FileItem.ID,
) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: 9,
        fileIDs: fileIDs,
        candidates: [],
        recommendedFileID: recommendedFileID,
        secondBestFileID: secondBestFileID,
        confidence: .medium,
        reviewState: .algorithmReviewed,
        isSafeForOneClickCulling: true,
        reasons: [],
        cautions: [],
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
private final class ControlledComparisonSessionImageService: ComparisonSessionImageServing {
    private struct ReloadRequest {
        let continuation: CheckedContinuation<ComparisonImageState, Never>
    }

    private var reloadRequests: [ReloadRequest] = []
    private var reloadCountWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    var cancelCount = 0

    func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool]
    ) {
        ([:], sourceFlags)
    }

    func reloadImage(
        for file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
    ) async -> ComparisonImageState {
        await withCheckedContinuation { continuation in
            reloadRequests.append(ReloadRequest(continuation: continuation))
            resumeSatisfiedWaiters()
        }
    }

    func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
    ) async -> [FileItem.ID: ComparisonImageState] {
        states
    }

    func cancel() {
        cancelCount += 1
    }

    func waitForReloadCount(_ count: Int) async {
        guard reloadRequests.count < count else { return }
        await withCheckedContinuation { continuation in
            reloadCountWaiters.append((count, continuation))
        }
    }

    func completeReload(at index: Int, with state: ComparisonImageState) {
        reloadRequests[index].continuation.resume(returning: state)
    }

    private func resumeSatisfiedWaiters() {
        let satisfied = reloadCountWaiters.filter { reloadRequests.count >= $0.count }
        reloadCountWaiters.removeAll { reloadRequests.count >= $0.count }
        satisfied.forEach { $0.continuation.resume() }
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
    func `presentation reuses display mapping and owns finalist focus`() {
        let first = makeComparisonSessionFile("first.ARW")
        let second = makeComparisonSessionFile("second.ARW")
        let third = makeComparisonSessionFile("third.ARW")
        let files = [first, second, third]
        let result = makeComparisonSessionBurstResult(
            fileIDs: files.map(\.id),
            recommendedFileID: third.id,
            secondBestFileID: first.id,
        )
        let selection = ComparisonSessionSelectionSpy()
        let model = makeModel(selection: selection)

        model.ensureValidSelection(in: files)
        #expect(selection.selectedFileID == first.id)

        #expect(model.focusFinalists(in: result))
        let focused = model.presentation(
            filteredFiles: files,
            comparisonFileIDs: files.map(\.id),
            activeBurstComparisonGroupID: result.groupID,
            burstAnalysisResult: { _ in result },
        )

        #expect(focused.files.map(\.id) == [third.id, first.id])
        #expect(focused.selectedComparisonFile?.id == third.id)
        #expect(focused.loadKey == [third.id, first.id].map(\.uuidString).joined(separator: ","))

        model.showAllCandidates(in: files)
        let allCandidates = model.presentation(
            filteredFiles: files,
            comparisonFileIDs: files.map(\.id),
            activeBurstComparisonGroupID: result.groupID,
            burstAnalysisResult: { _ in result },
        )
        #expect(allCandidates.files.map(\.id) == files.map(\.id))
        #expect(selection.selectedFileID == third.id)
    }

    @Test
    func `image intents route through the injected image service`() async {
        let file = makeComparisonSessionFile("image.ARW")
        let sourceFlags = [file.id: true]
        let imageService = ComparisonSessionImageServiceSpy()
        let model = makeModel(imageService: imageService)

        model.setUsesThumbnailSource(true, for: file.id)
        await model.loadImages(files: [file])
        await model.reload(file)
        await model.regenerateFocusMasks(files: [file])

        #expect(imageService.loadedFiles.map(\.id) == [file.id])
        #expect(imageService.loadedSourceFlags == sourceFlags)
        #expect(imageService.reloadedFile?.id == file.id)
        #expect(imageService.reloadedSourceFlags == sourceFlags)
        #expect(imageService.regeneratedFiles.map(\.id) == [file.id])
        #expect(model.imageStates[file.id]?.id == file.id)
    }

    @Test
    func `newer reload wins when an older request finishes last`() async {
        let file = makeComparisonSessionFile("stale.ARW")
        let imageService = ControlledComparisonSessionImageService()
        let model = ComparisonSessionModel(
            imageService: imageService,
            selection: ComparisonSessionSelectionSpy(),
        )

        let older = Task { await model.reload(file) }
        await imageService.waitForReloadCount(1)
        let newer = Task { await model.reload(file) }
        await imageService.waitForReloadCount(2)

        imageService.completeReload(
            at: 1,
            with: ComparisonImageState(
                id: file.id,
                isLoading: false,
                isFocusAnalysisComplete: true,
            ),
        )
        await newer.value
        imageService.completeReload(
            at: 0,
            with: ComparisonImageState(
                id: file.id,
                isLoading: false,
                isFocusAnalysisComplete: false,
            ),
        )
        await older.value

        #expect(model.imageStates[file.id]?.isFocusAnalysisComplete == true)
    }

    @Test
    func `cancellation prevents an in flight reload from publishing`() async {
        let file = makeComparisonSessionFile("cancelled.ARW")
        let imageService = ControlledComparisonSessionImageService()
        let model = ComparisonSessionModel(
            imageService: imageService,
            selection: ComparisonSessionSelectionSpy(),
        )

        let reload = Task { await model.reload(file) }
        await imageService.waitForReloadCount(1)
        model.cancel()
        imageService.completeReload(
            at: 0,
            with: ComparisonImageState(
                id: file.id,
                isLoading: false,
                isFocusAnalysisComplete: true,
            ),
        )
        await reload.value

        #expect(model.imageStates[file.id]?.isLoading == true)
        #expect(model.imageStates[file.id]?.isFocusAnalysisComplete == false)
        #expect(imageService.cancelCount == 1)
    }

    private func makeModel(
        imageService: ComparisonSessionImageServiceSpy = ComparisonSessionImageServiceSpy(),
        selection: ComparisonSessionSelectionSpy = ComparisonSessionSelectionSpy(),
    ) -> ComparisonSessionModel {
        ComparisonSessionModel(imageService: imageService, selection: selection)
    }
}
