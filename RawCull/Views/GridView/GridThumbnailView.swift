//
//  GridThumbnailView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import SwiftUI

struct GridThumbnailView: View {
    @Environment(GridThumbnailViewModel.self) var gridthumbnailviewmodel
    @Environment(SettingsViewModel.self) var settingsviewmodel

    var body: some View {
        Group {
            if let viewModel = gridthumbnailviewmodel.viewModel,
               let cullingModel = gridthumbnailviewmodel.cullingModel {
                GridThumbnailSelectionView(
                    viewModel: viewModel,
                    cullingManager: cullingModel,
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
    }
}
