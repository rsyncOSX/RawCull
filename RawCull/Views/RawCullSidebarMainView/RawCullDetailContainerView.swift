import SwiftUI

struct RawCullDetailContainerView: View {
    @Bindable var viewModel: RawCullViewModel
    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: FileItem.ID?
    @Binding var scale: CGFloat
    @Binding var lastScale: CGFloat
    @Binding var offset: CGSize
    let handleToggleSelection: (FileItem) -> Void
    let abort: () -> Void

    var body: some View {
        FileDetailView(
            viewModel: viewModel,
            cgImage: $cgImage,
            nsImage: $nsImage,
            selectedFileID: $selectedFileID,
            scale: $scale,
            lastScale: $lastScale,
            offset: $offset,
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
        if viewModel.focushideInspector == true {
            HideInspectorFocusView(
                focushideInspector: $viewModel.focushideInspector,
                hideInspector: $viewModel.hideInspector,
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
