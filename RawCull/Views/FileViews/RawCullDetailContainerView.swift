import RawCullCore
import SwiftUI

struct RawCullDetailContainerView: View {
    @Bindable var viewModel: RawCullViewModel
    let semanticSearchFeature: RawCullSemanticSearchFeature
    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: FileItem.ID?
    let abort: () -> Void

    var body: some View {
        FileDetailView(
            viewModel: viewModel,
            semanticSearchFeature: semanticSearchFeature,
            cgImage: $cgImage,
            nsImage: $nsImage,
            selectedFileID: $selectedFileID,
            file: viewModel.selectedFile,
        )

        // Move the conditional labels inside the ZStack so they participate in the ViewBuilder

        if viewModel.focusaborttask {
            AbortTaskFocusView(
                focusaborttask: $viewModel.focusaborttask,
                abort: abort,
            )
        }
    }
}
