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
    var cullingModel: CullingModel?
    var selectedSource: ARWSourceCatalog?
    var filteredFiles: [FileItem] = []
    var shouldShowWindow = false

    func open(
        cullingModel: CullingModel,
        selectedSource: ARWSourceCatalog?,
        filteredFiles: [FileItem]
    ) {
        self.cullingModel = cullingModel
        self.selectedSource = selectedSource
        self.filteredFiles = filteredFiles
        guard self.cullingModel != nil else { return }

        self.shouldShowWindow = true
    }

    func close() {
        shouldShowWindow = false
        cullingModel = nil
        selectedSource = nil
        filteredFiles = []
    }
}
