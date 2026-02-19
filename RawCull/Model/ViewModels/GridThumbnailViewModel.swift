//
//  GridThumbnailViewModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class GridThumbnailViewModel {
    var viewModel: RawCullViewModel?
    var cullingModel: CullingModel?
    var selectedSource: ARWSourceCatalog?
    var filteredFiles: [FileItem] = []
    var shouldShowWindow = false

    func open(
        viewModel: RawCullViewModel,
        cullingManager: CullingModel,
        selectedSource: ARWSourceCatalog?,
        filteredFiles: [FileItem]
    ) {
        self.viewModel = viewModel
        self.cullingModel = cullingManager
        self.selectedSource = selectedSource
        self.filteredFiles = filteredFiles
        self.shouldShowWindow = true
    }

    func close() {
        shouldShowWindow = false
        viewModel = nil
        cullingModel = nil
        selectedSource = nil
        filteredFiles = []
    }
}
