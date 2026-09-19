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

    var body: some View {
        if let signature = BurstGroupSignature(
            files: files,
            catalog: viewModel.selectedSource?.url,
        ) {
            DeepAIReviewSheetView(
                controller: controller,
                groupID: signature.hashValue,
                groupSignature: signature,
                files: files,
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
