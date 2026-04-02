import SwiftUI

struct TaggedPhotoHorisontalGridView: View {
    @Bindable var viewModel: RawCullViewModel
    @Environment(SettingsViewModel.self) private var settings

    var files: [FileItem]
    let catalogURL: URL?
    var onPhotoSelected: (FileItem) -> Void = { _ in }

    var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: CGFloat(settings.thumbnailSizeGrid)), spacing: 8)
                ],
                spacing: 8,
            ) {
                if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == catalogURL }) {
                    if let filerecords = cullingModel.savedFiles[index].filerecords {
                        let localfiles = filerecords
                            .filter { ($0.rating ?? 0) >= 2 }
                            .compactMap { $0.fileName }
                        ForEach(localfiles.sorted(), id: \.self) { photo in
                            let photoFileURL = files.first(where: { $0.name == photo })?.url
                            let photoFile = files.first(where: { $0.name == photo })
                            TaggedPhotoItemView(
                                viewModel: viewModel,
                                photo: photo,
                                photoURL: photoFileURL,
                                catalogURL: catalogURL,
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

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}
