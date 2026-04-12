import SwiftUI

struct RawCullDetailContainerView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: FileItem.ID?
    let handleToggleSelection: (FileItem) -> Void
    let abort: () -> Void

    var body: some View {
        FileDetailView(
            viewModel: viewModel,
            cgImage: $cgImage,
            nsImage: $nsImage,
            selectedFileID: $selectedFileID,
            file: viewModel.selectedFile,
        )

        // Move the conditional labels inside the ZStack so they participate in the ViewBuilder
        if viewModel.focustagimage == true {
            TagImageFocusView(
                focustagimage: $viewModel.focustagimage,
                files: viewModel.files,
                selectedFileID: selectedFileID,
                handleToggleSelection: handleToggleSelection,
            )
        }
        if viewModel.focusaborttask {
            AbortTaskFocusView(
                focusaborttask: $viewModel.focusaborttask,
                abort: abort,
            )
        }

        if viewModel.focusExtractJPGs {
            ExtractJPGsFocusView(
                selectedSource: viewModel.selectedSource,
                alertType: $viewModel.alertType,
                showingAlert: $viewModel.showingAlert,
            )
        }
    }
}
