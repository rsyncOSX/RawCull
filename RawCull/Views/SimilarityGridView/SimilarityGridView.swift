//
//  SimilarityGridView.swift
//  RawCull
//
//  Similarity-focused alternative to GridThumbnailView. Hosts only similarity
//  indexing and burst grouping; sharpness scoring runs as a silent
//  prerequisite controlled by a toolbar toggle inside the selection view.
//

import SwiftUI

struct SimilarityGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        Group {
            if gridthumbnailviewmodel.cullingModel != nil {
                SimilarityGridSelectionView(
                    viewModel: viewModel,
                    nsImage: $nsImage,
                    cgImage: $cgImage,
                )
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "photo.fill",
                    description: Text("Please select a source from the main window to view thumbnails."),
                )
            }
        }
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }
    }

    private func navigateToNext() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index + 1 < sortedFiles.count else { return }
        viewModel.selectedFileID = sortedFiles[index + 1].id
    }

    private func navigateToPrevious() {
        guard let current = viewModel.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        viewModel.selectedFileID = sortedFiles[index - 1].id
    }

    private var filteredFiles: [FileItem] {
        viewModel.filteredFiles.filter { viewModel.passesRatingFilter($0) }
    }

    private var sortedFiles: [FileItem] {
        if viewModel.similarityModel.burstModeActive,
           !viewModel.similarityModel.burstGroups.isEmpty {
            let visible = Dictionary(uniqueKeysWithValues: filteredFiles.map { ($0.id, $0) })
            return viewModel.similarityModel.burstGroups.flatMap { group in
                group.fileIDs.compactMap { visible[$0] }
            }
        }
        guard !viewModel.sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
