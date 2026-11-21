import Foundation
import Observation
import OSLog
import RawCullCore

/// Which photos are selected in the workspace: the current file, the
/// multi-selection, the comparison set and the order the culling grid shows.
@Observable @MainActor
final class SelectionModel: ImageReviewSelectionActing, ComparisonSessionSelection {
    var selectedFileID: FileItem.ID?
    var selectedFileIDs: Set<FileItem.ID> = []
    /// Ordered IDs currently rendered by the culling grid. Keyboard and loupe
    /// navigation use this projection so hidden burst frames cannot become targets.
    var cullingGridRenderedFileIDs: [FileItem.ID] = []
    var comparisonFileIDs: [FileItem.ID] = []

    func select(_ file: FileItem) {
        Logger.process.debugMessageOnly("SelectionModel.select()")
        selectedFileID = file.id
    }

    /// Selects the first of `files` in name order, or nothing when empty.
    func selectFirstByName(in files: [FileItem]) {
        selectedFileID = files
            .min { lhs, rhs in
                lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }?
            .id
    }
}
