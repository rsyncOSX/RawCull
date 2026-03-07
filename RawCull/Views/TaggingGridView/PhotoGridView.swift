import SwiftUI

struct PhotoGridView: View {
    // Use @State for Observable objects in the view that owns them
    @Bindable var cullingModel: CullingModel
    @State private var savedSettings: SavedSettings?
    var files: [FileItem]
    let photoURL: URL?
    var onPhotoSelected: (FileItem) -> Void = { _ in }
    var body: some View {
        ScrollView(.horizontal) {
            if savedSettings != nil {
                LazyHStack(alignment: .top, spacing: 10) {
                    if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == photoURL }) {
                        if let filerecords = cullingModel.savedFiles[index].filerecords {
                            let localfiles = filerecords.compactMap { record in record.fileName }
                            ForEach(localfiles.sorted(), id: \.self) { photo in
                                let photoURL = files.first(where: { $0.name == photo })?.url
                                let photoFile = files.first(where: { $0.name == photo })
                                PhotoItemView(
                                    photo: photo,
                                    photoURL: photoURL,
                                    onSelected: {
                                        if let file = photoFile {
                                            onPhotoSelected(file)
                                        }
                                    },
                                    cullingModel: cullingModel
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }
}
