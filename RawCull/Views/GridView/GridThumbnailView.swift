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
    @Environment(SettingsViewModel.self) var settingsviewmodel

    var body: some View {
        Group {
            if let cullingModel = gridthumbnailviewmodel.cullingModel {
                GridThumbnailSelectionView(
                    viewModel: viewModel,
                    cullingModel: cullingModel,
                    files: gridthumbnailviewmodel.filteredFiles,
                    selectedSource: gridthumbnailviewmodel.selectedSource
                )
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "photo.fill",
                    description: Text("Please select a source from the main window to view thumbnails.")
                )
            }
        }
        .onDisappear {
            gridthumbnailviewmodel.close()
        }
        .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
        .focusable()
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }

        if viewModel.focustagimage == true { labeltagimage }
    }

    var labeltagimage: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                viewModel.focustagimage = false
                if let index = viewModel.files.firstIndex(where: { $0.id == viewModel.selectedFileID }) {
                    let fileitem = viewModel.files[index]
                    handleToggleSelection(for: fileitem)
                }
            }
    }

    private func handleToggleSelection(for file: FileItem) {
        Task {
            await gridthumbnailviewmodel.cullingModel?.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name
            )
        }
    }

    private func navigateToNext() {
        guard let current = viewModel.selectedFile,
              let index = files.firstIndex(where: { $0.id == current.id }),
              index + 1 < files.count else { return }
        viewModel.selectedFile = files[index + 1]
    }

    private func navigateToPrevious() {
        guard let current = viewModel.selectedFile,
              let index = files.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        viewModel.selectedFile = files[index - 1]
    }

    var files: [FileItem] {
        viewModel.files
    }
}
