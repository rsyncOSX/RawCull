import Foundation
import Observation
import RawCullCore

/// The existing comparison image pipeline includes decoding, thumbnail-cache
/// access, and focus analysis. Keeping it behind one boundary makes those live
/// services injectable without changing their behavior during the shell phase.
@MainActor
protocol ComparisonSessionImageServing: AnyObject {
    func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool],
    )

    func reloadImage(
        for file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
    ) async -> ComparisonImageState

    func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
    ) async -> [FileItem.ID: ComparisonImageState]

    func cancel()
}

@MainActor
protocol ComparisonSessionSelection: AnyObject {
    var selectedFileID: FileItem.ID? { get set }
}

extension RawCullViewModel: ComparisonSessionSelection {}

struct ComparisonSessionPresentation {
    let displayState: ComparisonGridDisplayState
    let imageStates: [FileItem.ID: ComparisonImageState]

    var files: [FileItem] {
        displayState.files
    }

    var allComparisonFiles: [FileItem] {
        displayState.allComparisonFiles
    }

    var selectedComparisonFile: FileItem? {
        displayState.selectedComparisonFile
    }

    var burstComparisonResult: BurstAnalysisResult? {
        displayState.burstComparisonResult
    }

    var loadKey: String {
        displayState.loadKey
    }
}

@MainActor
final class LiveComparisonSessionImageService: ComparisonSessionImageServing {
    private let viewModel: RawCullViewModel

    init(viewModel: RawCullViewModel) {
        self.viewModel = viewModel
    }

    func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool],
    ) {
        await ComparisonGridImageCoordinator.loadImages(
            files: files,
            sourceFlags: sourceFlags,
            viewModel: viewModel,
        )
    }

    func reloadImage(
        for file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
    ) async -> ComparisonImageState {
        await ComparisonGridImageCoordinator.reloadImage(
            for: file,
            sourceFlags: sourceFlags,
            viewModel: viewModel,
        )
    }

    func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
    ) async -> [FileItem.ID: ComparisonImageState] {
        await ComparisonGridImageCoordinator.regenerateFocusMasks(
            files: files,
            states: states,
            viewModel: viewModel,
        )
    }

    func cancel() {
        // The session owns and cancels the structured tasks that invoke this
        // service. The live coordinator has no additional task registry.
    }
}

@MainActor
@Observable
final class ComparisonSessionModel {
    private(set) var isActive = false
    private(set) var finalistFocusActive = false
    private(set) var imageStates: [FileItem.ID: ComparisonImageState] = [:]
    private(set) var viewportStatesByFileID: [FileItem.ID: ComparisonViewportInteractionState] = [:]
    private(set) var useThumbnailSourceByFileID: [FileItem.ID: Bool] = [:]

    @ObservationIgnored private let imageService: any ComparisonSessionImageServing
    @ObservationIgnored private let selection: any ComparisonSessionSelection
    @ObservationIgnored private var bulkLoadTask: Task<(
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool]
    ), Never>?
    @ObservationIgnored private var reloadTasksByFileID: [FileItem.ID: Task<ComparisonImageState, Never>] = [:]
    @ObservationIgnored private var focusRegenerationTask: Task<[FileItem.ID: ComparisonImageState], Never>?
    @ObservationIgnored private var reloadGenerationByFileID: [FileItem.ID: UUID] = [:]
    @ObservationIgnored private var bulkLoadGeneration: UUID?
    @ObservationIgnored private var focusRequestTracker = ImageReviewRequestTracker<ImageReviewFocusRequestContext>()
    @ObservationIgnored private var imageMutationRevision = 0

    init(
        imageService: any ComparisonSessionImageServing,
        selection: any ComparisonSessionSelection,
    ) {
        self.imageService = imageService
        self.selection = selection
    }

    func activate() {
        isActive = true
    }

    func select(_ fileID: FileItem.ID?) {
        selection.selectedFileID = fileID
    }

    func moveSelection(
        _ direction: ComparisonGridNavigationDirection,
        in files: [FileItem],
    ) {
        guard let selectedID = selection.selectedFileID,
              let currentIndex = files.firstIndex(where: { $0.id == selectedID }),
              let destinationIndex = ComparisonGridNavigation.destinationIndex(
                  from: currentIndex,
                  itemCount: files.count,
                  direction: direction,
              )
        else { return }

        select(files[destinationIndex].id)
    }

    func ensureValidSelection(in files: [FileItem]) {
        guard let first = files.first else { return }
        if let selectedID = selection.selectedFileID,
           files.contains(where: { $0.id == selectedID }) {
            return
        }
        select(first.id)
    }

    func focusFinalists(in result: BurstAnalysisResult?) -> Bool {
        let finalistIDs = ComparisonFinalistFocus.focusedIDs(from: result)
        guard let firstFinalistID = finalistIDs.first else { return false }
        finalistFocusActive = true
        select(firstFinalistID)
        return true
    }

    func showAllCandidates(in files: [FileItem]) {
        finalistFocusActive = false
        ensureValidSelection(in: files)
    }

    func resetDisplayScope() {
        finalistFocusActive = false
        resetViewportStates()
    }

    func presentation(
        filteredFiles: [FileItem],
        comparisonFileIDs: [FileItem.ID],
        activeBurstComparisonGroupID: Int?,
        burstAnalysisResult: (Int) -> BurstAnalysisResult?,
    ) -> ComparisonSessionPresentation {
        ComparisonSessionPresentation(
            displayState: ComparisonGridDisplayState(
                filteredFiles: filteredFiles,
                comparisonFileIDs: comparisonFileIDs,
                selectedFileID: selection.selectedFileID,
                activeBurstComparisonGroupID: activeBurstComparisonGroupID,
                finalistFocusActive: finalistFocusActive,
                burstAnalysisResult: burstAnalysisResult,
            ),
            imageStates: imageStates,
        )
    }

    func viewportState(for fileID: FileItem.ID) -> ComparisonViewportInteractionState {
        viewportStatesByFileID[fileID] ?? ComparisonViewportInteractionState()
    }

    func setViewportState(
        _ state: ComparisonViewportInteractionState,
        for fileID: FileItem.ID,
    ) {
        viewportStatesByFileID[fileID] = state
    }

    func usesThumbnailSource(for fileID: FileItem.ID) -> Bool {
        useThumbnailSourceByFileID[fileID] ?? false
    }

    func setUsesThumbnailSource(_ useThumbnail: Bool, for fileID: FileItem.ID) {
        useThumbnailSourceByFileID[fileID] = useThumbnail
    }

    func resetViewportStates() {
        viewportStatesByFileID = [:]
    }

    func loadImages(files: [FileItem]) async {
        bulkLoadTask?.cancel()

        let generation = UUID()
        let mutationRevision = imageMutationRevision
        let sourceFlags = useThumbnailSourceByFileID
        bulkLoadGeneration = generation

        let task = Task {
            await imageService.loadImages(files: files, sourceFlags: sourceFlags)
        }
        bulkLoadTask = task
        let result = await task.value

        guard ComparisonGridImageCompletionPolicy.acceptsBulkLoad(
            isCancelled: task.isCancelled,
            generation: generation,
            currentGeneration: bulkLoadGeneration,
            mutationRevision: mutationRevision,
            currentMutationRevision: imageMutationRevision,
        ) else { return }

        imageStates = result.states
        useThumbnailSourceByFileID = result.sourceFlags
        bulkLoadTask = nil
        bulkLoadGeneration = nil
    }

    func reload(_ file: FileItem) async {
        reloadTasksByFileID[file.id]?.cancel()
        imageMutationRevision &+= 1

        let generation = UUID()
        let sourceFlags = useThumbnailSourceByFileID
        reloadGenerationByFileID[file.id] = generation
        imageStates[file.id] = ComparisonImageState(id: file.id, isLoading: true)

        let task = Task {
            await imageService.reloadImage(for: file, sourceFlags: sourceFlags)
        }
        reloadTasksByFileID[file.id] = task
        let state = await task.value

        guard ComparisonGridImageCompletionPolicy.acceptsReload(
            isCancelled: task.isCancelled,
            generation: generation,
            currentGeneration: reloadGenerationByFileID[file.id],
        ) else { return }

        imageStates[file.id] = state
        reloadTasksByFileID[file.id] = nil
        reloadGenerationByFileID[file.id] = nil
    }

    func regenerateFocusMasks(files: [FileItem]) async {
        focusRegenerationTask?.cancel()

        let mutationRevision = imageMutationRevision
        let states = imageStates
        let request = focusRequestTracker.begin(
            context: ImageReviewFocusRequestContext(fileIDs: files.map(\.id)),
        )

        let task = Task {
            await imageService.regenerateFocusMasks(files: files, states: states)
        }
        focusRegenerationTask = task
        let updatedStates = await task.value

        let acceptsResult = focusRequestTracker.accepts(
            request,
            isCancelled: task.isCancelled,
            requestRevision: mutationRevision,
            currentRevision: imageMutationRevision,
        )
        if focusRequestTracker.current == request {
            focusRegenerationTask = nil
            focusRequestTracker.finish(request)
        }
        guard acceptsResult else { return }

        imageStates = updatedStates
    }

    func cancel() {
        isActive = false
        bulkLoadTask?.cancel()
        bulkLoadTask = nil
        bulkLoadGeneration = nil
        reloadTasksByFileID.values.forEach { $0.cancel() }
        reloadTasksByFileID = [:]
        reloadGenerationByFileID = [:]
        focusRegenerationTask?.cancel()
        focusRegenerationTask = nil
        focusRequestTracker.cancel()
        imageService.cancel()
    }
}
