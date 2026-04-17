//
//  GridThumbnailView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import SwiftUI

struct GridThumbnailView: View {
    @Bindable var viewModel: RawCullViewModel
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        // let _ = Self._printChanges()
        Group {
            if gridthumbnailviewmodel.cullingModel != nil {
                GridThumbnailSelectionView(
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
        .onDisappear {
            gridthumbnailviewmodel.close()
        }
        // .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }

        if viewModel.focustagimage == true {
            TagImageFocusView(
                focustagimage: $viewModel.focustagimage,
                files: viewModel.files,
                selectedFileID: viewModel.selectedFileID,
                handleToggleSelection: handleToggleSelection,
            )
        }
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await viewModel.toggleTag(for: file)
        }
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
        guard !viewModel.sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
