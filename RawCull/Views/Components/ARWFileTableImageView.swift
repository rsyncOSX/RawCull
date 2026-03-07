//
//  ARWFileTableImageView.swift
//  RawCull
//
//  Created by Thomas Evensen on 06/03/2026.
//

import SwiftUI

/*
 isHovered: hoveredFileID == file.id,
 onToggle: { handleToggleSelection(for: file) },
 onSelected: {
     viewModel.selectedFileID = file.id
     viewModel.selectedFile = file
 }
 */

struct ARWFileTableImageView: View {
    @Bindable var viewModel: RawCullViewModel
    let files: [FileItem]
    let selectedSource: ARWSourceCatalog?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(files, id: \.id) { file in
                            ARWFileTableItemView(
                                viewModel: viewModel,
                                file: file,
                                selectedSource: selectedSource
                            )
                            .id(file.id)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        viewModel.selectedFile?.id == file.id ? Color.accentColor : Color.clear,
                                        lineWidth: 3
                                    )
                            )
                            .onTapGesture {
                                handleSelection(file: file)
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

    private func handleSelection(file: FileItem) {
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
}
