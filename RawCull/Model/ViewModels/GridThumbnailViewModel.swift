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

    func open(
        cullingModel: CullingModel,
        selectedSource: ARWSourceCatalog?,
        filteredFiles: [FileItem],
    ) {
        self.cullingModel = cullingModel
        self.selectedSource = selectedSource
        self.filteredFiles = filteredFiles
    }

    func close() {
        cullingModel = nil
        selectedSource = nil
        filteredFiles = []
    }
}
