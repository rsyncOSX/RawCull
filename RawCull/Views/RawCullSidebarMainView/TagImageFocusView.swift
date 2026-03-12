import SwiftUI

struct TagImageFocusView: View {
    @Binding var focustagimage: Bool
    let files: [FileItem]
    let selectedFileID: FileItem.ID?
    let handleToggleSelection: (FileItem) -> Void

    var body: some View {
        Label("", systemImage: "play.fill")
            .onAppear {
                focustagimage = false
                if let index = files.firstIndex(where: { $0.id == selectedFileID }) {
                    let fileitem = files[index]
                    handleToggleSelection(fileitem)
                }
            }
    }
}
