import SwiftUI

struct TaggedPhotoHorisontalGridView: View {
    @Bindable var viewModel: RawCullViewModel
    private var settings: SettingsViewModel { SettingsViewModel.shared }

    let catalogURL: URL?
    var onPhotoSelected: (FileItem) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    viewModel.cullingModel.loadSavedFiles()
                    viewModel.rebuildRatingCache()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reload rated images from disk")
                .padding(.horizontal)
                .padding(.vertical, 6)
            }
            .background(.bar)

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
                                let photoFileURL = viewModel.filteredFiles.first(where: { $0.name == photo })?.url
                                let photoFile = viewModel.filteredFiles.first(where: { $0.name == photo })
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
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }
}
