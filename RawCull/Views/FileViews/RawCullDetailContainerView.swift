import RawCullCore
import SwiftUI

struct RawCullDetailContainerView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(WorkspacePresentationModel.self) private var presentation
    @Environment(SelectionModel.self) private var selection
    let semanticSearchFeature: RawCullSemanticSearchFeature
    @Binding var cgImage: CGImage?
    @Binding var nsImage: NSImage?
    @Binding var selectedFileID: FileItem.ID?
    let abort: () -> Void

    var body: some View {
        FileDetailView(semanticSearchFeature: semanticSearchFeature,
            cgImage: $cgImage,
            nsImage: $nsImage,
            selectedFileID: $selectedFileID,
            file: catalog.file(withID: selection.selectedFileID),
        )

        // Move the conditional labels inside the ZStack so they participate in the ViewBuilder

        if presentation.focusAbortTask {
            AbortTaskFocusView(
                focusAbortTask: Bindable(presentation).focusAbortTask,
                abort: abort,
            )
        }
    }
}
