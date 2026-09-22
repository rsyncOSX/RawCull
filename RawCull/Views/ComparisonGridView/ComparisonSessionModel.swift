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
        // The live pipeline uses structured task cancellation. Task ownership
        // remains in ComparisonGridView until commit 3.3.
    }
}

@MainActor
@Observable
final class ComparisonSessionModel {
    private(set) var isActive = false

    @ObservationIgnored private let imageService: any ComparisonSessionImageServing
    @ObservationIgnored private let selection: any ComparisonSessionSelection

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

    func loadImages(
        files: [FileItem],
        sourceFlags: [FileItem.ID: Bool],
    ) async -> (
        states: [FileItem.ID: ComparisonImageState],
        sourceFlags: [FileItem.ID: Bool],
    ) {
        await imageService.loadImages(files: files, sourceFlags: sourceFlags)
    }

    func reload(
        _ file: FileItem,
        sourceFlags: [FileItem.ID: Bool],
    ) async -> ComparisonImageState {
        await imageService.reloadImage(for: file, sourceFlags: sourceFlags)
    }

    func regenerateFocusMasks(
        files: [FileItem],
        states: [FileItem.ID: ComparisonImageState],
    ) async -> [FileItem.ID: ComparisonImageState] {
        await imageService.regenerateFocusMasks(files: files, states: states)
    }

    func cancel() {
        isActive = false
        imageService.cancel()
    }
}
