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

    @Binding var isPresented: Bool

    var body: some View {
        // let _ = Self._printChanges()
        Group {
            if gridthumbnailviewmodel.cullingModel != nil {
                GridThumbnailSelectionView(
                    viewModel: viewModel,
                    selectedSource: gridthumbnailviewmodel.selectedSource,
                )
            } else {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "photo.fill",
                    description: Text("Please select a source from the main window to view thumbnails."),
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: { isPresented = false }) {
                    Label("Back", systemImage: "chevron.left")
                }
                .help("Return to main view")
            }
        }
        .onDisappear {
            gridthumbnailviewmodel.close()
        }
        .focusedSceneValue(\.tagimage, $viewModel.focustagimage)
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
            await gridthumbnailviewmodel.cullingModel?.toggleSelectionSavedFiles(
                in: file.url,
                toggledfilename: file.name,
            )
            navigateToNext()
        }
    }

    private func navigateToNext() {
        guard let current = viewModel.selectedFile,
              let index = files.firstIndex(where: { $0.id == current.id }),
              index + 1 < files.count else { return }
        viewModel.selectedFile = files[index + 1]
        viewModel.selectedFileID = files[index + 1].id
    }

    private func navigateToPrevious() {
        guard let current = viewModel.selectedFile,
              let index = files.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        viewModel.selectedFile = files[index - 1]
        viewModel.selectedFileID = files[index - 1].id
    }

    var files: [FileItem] {
        viewModel.files
    }
}
