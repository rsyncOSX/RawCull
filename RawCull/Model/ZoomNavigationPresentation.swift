import Foundation

@MainActor
struct ZoomNavigationPresentation {
    let viewModel: RawCullViewModel

    var orderedZoomFiles: [FileItem] {
        if let context = viewModel.zoomOverlayNavigationContext {
            let filesByID = Dictionary(uniqueKeysWithValues: viewModel.files.map { ($0.id, $0) })
            let contextualFiles = context.orderedFileIDs.compactMap { filesByID[$0] }
            if !contextualFiles.isEmpty {
                return contextualFiles
            }
        }

        let filtered = viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
        let usesAnalysisSortOrder =
            viewModel.sharpnessModel.sortBySharpness
            || viewModel.similarityFeature.isSimilaritySortingActive
        return usesAnalysisSortOrder
            ? filtered
            : filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var currentZoomIndex: Int? {
        guard let selectedFile = viewModel.selectedFile else { return nil }
        return orderedZoomFiles.firstIndex { $0.id == selectedFile.id }
    }

    var canNavigatePrevious: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex > 0
    }

    var canNavigateNext: Bool {
        guard let currentZoomIndex else { return false }
        return currentZoomIndex + 1 < orderedZoomFiles.count
    }
}
