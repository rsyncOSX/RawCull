import SwiftUI

struct TaggedPhotoHorisontalGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @State private var savedSettings: SavedSettings?
    var files: [FileItem]
    let photoURL: URL?
    var onPhotoSelected: (FileItem) -> Void = { _ in }

    var body: some View {
        ScrollView {
            if let savedSettings {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: CGFloat(savedSettings.thumbnailSizeGrid)), spacing: 8)
                    ],
                    spacing: 8,
                ) {
                    if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == photoURL }) {
                        if let filerecords = cullingModel.savedFiles[index].filerecords {
                            let localfiles = filerecords.compactMap { record in record.fileName }
                            ForEach(localfiles.sorted(), id: \.self) { photo in
                                let photoURL = files.first(where: { $0.name == photo })?.url
                                let photoFile = files.first(where: { $0.name == photo })
                                TaggedPhotoItemView(
                                    viewModel: viewModel,
                                    photo: photo,
                                    photoURL: photoURL,
                                    onSelected: {
                                        if let file = photoFile {
                                            onPhotoSelected(file)
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .task {
            savedSettings = await SettingsViewModel.shared.asyncgetsettings()
        }
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}
