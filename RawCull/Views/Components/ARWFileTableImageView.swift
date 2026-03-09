//
//  ARWFileTableImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

import SwiftUI

struct ARWFileTableImageView: View {
    @Bindable var viewModel: RawCullViewModel
    @Bindable var cullingModel: CullingModel

    let selectedSource: ARWSourceCatalog?

    @State private var hoveredFileID: FileItem.ID?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(files, id: \.id) { file in
                            ImageItemView(
                                viewModel: viewModel,
                                cullingModel: cullingModel,
                                file: file,
                                selectedSource: selectedSource,
                                isHovered: hoveredFileID == file.id,
                                gridview: false,
                                // One click for select only
                                onToggle: { handleToggleSelection(for: file) },
                                // Double clik for tag Image
                                onSelected: {
                                    Task {
                                        await cullingModel.toggleSelectionSavedFiles(
                                            in: file.url,
                                            toggledfilename: file.name
                                        )
                                    }
                                }
                            )
                            .id(file.id)
                            /*
                             .overlay(
                                 RoundedRectangle(cornerRadius: 6)
                                     .stroke(
                                         viewModel.selectedFile?.id == file.id ? Color.accentColor : Color.clear,
                                         lineWidth: 3
                                     )
                             )
                              */
                            .onHover { isHovered in
                                hoveredFileID = isHovered ? file.id : nil
                            }
                        }
                    }
                }
                .onChange(of: viewModel.selectedFile?.id) { _, newID in
                    if let newID {
                        withAnimation {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
        .focusable()
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }
    }

    private func handleToggleSelection(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.selectedFile = file
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
