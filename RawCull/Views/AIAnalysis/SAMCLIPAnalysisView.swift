//
//  SAMCLIPAnalysisView.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/09/2026.
//

import SwiftUI

struct SAMCLIPAnalysisView: View {
    @Bindable var viewModel: RawCullViewModel
    let controller: DeepAIReviewController
    let files: [FileItem]
    @Binding var selection: UUID?

    private var pendingFiles: [FileItem] {
        controller.filesNeedingAnalysis(from: files)
    }

    var body: some View {
        if viewModel.selectedSource != nil || !controller.completedCandidates.isEmpty {
            let runnableFiles = viewModel.selectedSource == nil ? [] : pendingFiles
            let signature = BurstGroupSignature(
                files: runnableFiles,
                catalog: viewModel.selectedSource?.url,
            )
                ?? BurstGroupSignature(memberKeys: [])
            DeepAIReviewSheetView(
                controller: controller,
                groupID: signature.hashValue,
                groupSignature: signature,
                files: runnableFiles,
                selection: $selection,
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
