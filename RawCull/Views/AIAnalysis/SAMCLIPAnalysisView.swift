//
//  SAMCLIPAnalysisView.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/09/2026.
//

import SwiftUI

struct SAMCLIPAnalysisView: View {
    let catalog: CatalogWorkspace
    let controller: DeepAIReviewController
    let files: [FileItem]
    @Binding var selection: UUID?
    let focusMaskModel: FocusMaskModel
    let focusConfig: FocusDetectorConfig

    private var pendingFiles: [FileItem] {
        controller.filesNeedingAnalysis(from: files)
    }

    var body: some View {
        if catalog.selectedSource != nil || !controller.completedCandidates.isEmpty {
            let runnableFiles = catalog.selectedSource == nil ? [] : pendingFiles
            let signature = BurstGroupSignature(
                files: runnableFiles,
                catalog: catalog.selectedSource?.url,
            )
                ?? BurstGroupSignature(memberKeys: [])
            DeepAIReviewSheetView(
                controller: controller,
                groupID: signature.hashValue,
                groupSignature: signature,
                files: runnableFiles,
                selection: $selection,
                focusMaskModel: focusMaskModel,
                focusConfig: focusConfig,
            )
        } else {
            ContentUnavailableView(
                "Catalog Required",
                systemImage: "folder.badge.questionmark",
                description: Text("Select a catalog before running SAM 3 + CLIP analysis."),
            )
        }
    }
}
