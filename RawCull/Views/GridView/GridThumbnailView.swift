//
//  GridThumbnailView.swift
//  RawCull
//
//  Created by Thomas Evensen on 13/02/2026.
//

import SwiftUI

struct GridThumbnailView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(RatingsModel.self) private var ratings
    @Environment(WorkspaceNavigationModel.self) private var navigation
    @Environment(CatalogController.self) private var catalogController
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    let similarityFeature: RawCullSimilarityFeature
    let semanticSearchFeature: RawCullSemanticSearchFeature

    @Binding var nsImage: NSImage?
    @Binding var cgImage: CGImage?

    var body: some View {
        // let _ = Self._printChanges()
        Group {
            if navigation.canShowThumbnailWorkspace {
                GridThumbnailSelectionView(
                    similarityFeature: similarityFeature,
                    semanticSearchFeature: semanticSearchFeature,
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
        .focusable()
        .focusEffectDisabled(true)
        .onKeyPress(.leftArrow) { navigateToPrevious(); return .handled }
        .onKeyPress(.rightArrow) { navigateToNext(); return .handled }
    }

    private func navigateToNext() {
        guard let current = catalogController.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index + 1 < sortedFiles.count else { return }
        selection.selectedFileID = sortedFiles[index + 1].id
    }

    private func navigateToPrevious() {
        guard let current = catalogController.selectedFile,
              let index = sortedFiles.firstIndex(where: { $0.id == current.id }),
              index - 1 >= 0 else { return }
        selection.selectedFileID = sortedFiles[index - 1].id
    }

    private var filteredFiles: [FileItem] {
        catalog.filteredFiles.filter { ratings.passesRatingFilter($0) }
    }

    private var sortedFiles: [FileItem] {
        if navigation.showsBurstGroups,
           !similarityFeature.burstGroups.isEmpty {
            let visible = Dictionary(uniqueKeysWithValues: filteredFiles.map { ($0.id, $0) })
            if !selection.cullingGridRenderedFileIDs.isEmpty {
                return selection.cullingGridRenderedFileIDs.compactMap { visible[$0] }
            }
            return similarityFeature.burstGroups.flatMap { group in
                group.fileIDs.compactMap { visible[$0] }
            }
        }
        guard !sharpnessModel.sortBySharpness else { return filteredFiles }
        return filteredFiles.sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
