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
            // Grid view
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(files, id: \.id) { file in
                        ARWFileTableItemView(
                            viewModel: viewModel,
                            file: file,
                            selectedSource: selectedSource
                        )
                        .onTapGesture {
                            handleSelection(file: file)
                        }
                    }
                }
            }
        }
    }

    private func handleSelection(file: FileItem) {
        viewModel.selectedFile = file
    }
}
