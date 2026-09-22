import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeComparisonCoordinatorFile(_ name: String) -> FileItem {
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

private actor ComparisonLoadGate {
    private var hasStarted = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func load(_ file: FileItem) async -> ComparisonImageState {
        hasStarted = true
        startedContinuation?.resume()
        startedContinuation = nil
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        return ComparisonImageState(id: file.id, isLoading: false)
    }

    func waitUntilStarted() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
@Suite("ComparisonGridImageCoordinator")
struct ComparisonGridImageCoordinatorTests {
    @Test(.tags(.smoke))
    func `reload forwards the selected source for only the requested file`() async {
        let first = makeComparisonCoordinatorFile("first.ARW")
        let second = makeComparisonCoordinatorFile("second.ARW")
        var requests: [(FileItem.ID, Bool)] = []

        let state = await ComparisonGridImageCoordinator.reloadImage(
            for: second,
            sourceFlags: [first.id: false, second.id: true],
        ) { file, useThumbnailSource in
            requests.append((file.id, useThumbnailSource))
            return ComparisonImageState(id: file.id, isLoading: false)
        }

        #expect(requests.count == 1)
        #expect(requests.first?.0 == second.id)
        #expect(requests.first?.1 == true)
        #expect(state.id == second.id)
        #expect(!state.isLoading)
    }

    @Test(.tags(.smoke))
    func `cancelling a bulk load rejects the in flight result and stops later files`() async {
        let first = makeComparisonCoordinatorFile("first.ARW")
        let second = makeComparisonCoordinatorFile("second.ARW")
        let gate = ComparisonLoadGate()
        var requestedIDs: [FileItem.ID] = []

        let task = Task { @MainActor in
            await ComparisonGridImageCoordinator.loadImages(
                files: [first, second],
                sourceFlags: [:],
            ) { file, _ in
                requestedIDs.append(file.id)
                return await gate.load(file)
            }
        }

        await gate.waitUntilStarted()
        task.cancel()
        await gate.release()
        let result = await task.value

        #expect(requestedIDs == [first.id])
        #expect(result.states[first.id]?.isLoading == true)
        #expect(result.states[second.id]?.isLoading == true)
        #expect(result.sourceFlags == [first.id: false, second.id: false])
    }

    @Test(.tags(.smoke))
    func `out of order reload completion accepts only the newest generation`() {
        let older = UUID()
        let newer = UUID()

        #expect(!ComparisonGridImageCompletionPolicy.acceptsReload(
            isCancelled: false,
            generation: older,
            currentGeneration: newer,
        ))
        #expect(ComparisonGridImageCompletionPolicy.acceptsReload(
            isCancelled: false,
            generation: newer,
            currentGeneration: newer,
        ))
        #expect(!ComparisonGridImageCompletionPolicy.acceptsReload(
            isCancelled: true,
            generation: newer,
            currentGeneration: newer,
        ))
    }

    @Test(.tags(.smoke))
    func `bulk completion rejects work superseded by a reload`() {
        let generation = UUID()

        #expect(ComparisonGridImageCompletionPolicy.acceptsBulkLoad(
            isCancelled: false,
            generation: generation,
            currentGeneration: generation,
            mutationRevision: 3,
            currentMutationRevision: 3,
        ))
        #expect(!ComparisonGridImageCompletionPolicy.acceptsBulkLoad(
            isCancelled: false,
            generation: generation,
            currentGeneration: generation,
            mutationRevision: 3,
            currentMutationRevision: 4,
        ))
    }
}
