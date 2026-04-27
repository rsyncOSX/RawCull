import AppKit
import SwiftUI

struct RatedPhotoGridView: View {
    @Bindable var viewModel: RawCullViewModel
    private var settings: SettingsViewModel {
        SettingsViewModel.shared
    }

    let catalogURL: URL?
    var onPhotoSelected: (FileItem) -> Void = { _ in }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: CGFloat(settings.thumbnailSizeGrid)), spacing: 8)
                    ],
                    spacing: 8,
                ) {
                    ForEach(ratedFiles, id: \.id) { file in
                        RatedImageItemView(
                            viewModel: viewModel,
                            photo: file.name,
                            photoURL: file.url,
                            catalogURL: catalogURL,
                            isSelected: viewModel.selectedFileID == file.id,
                            isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
                            onSelected: { handleToggleSelection(for: file) },
                            onDoubleSelected: { handleDoubleSelect(for: file) },
                        )
                        .id(file.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.selectedFileID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .task(id: catalogURL) {
            viewModel.selectedFileIDs = []
        }
        .thumbnailKeyNavigation(viewModel: viewModel, axis: .grid) { ratedFiles }
    }

    var cullingModel: CullingModel {
        viewModel.cullingModel
    }

    private var ratedFiles: [FileItem] {
        guard let catalogURL,
              let entry = cullingModel.savedFiles.first(where: { $0.catalog == catalogURL }),
              let records = entry.filerecords else { return [] }
        let names = records
            .filter { ($0.rating ?? 0) >= 2 }
            .compactMap(\.fileName)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let byName = Dictionary(
            uniqueKeysWithValues: viewModel.filteredFiles.map { ($0.name, $0) },
        )
        return names.compactMap { byName[$0] }
    }

    private func handleToggleSelection(for file: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if viewModel.selectedFileIDs.contains(file.id) {
                viewModel.selectedFileIDs.remove(file.id)
            } else {
                viewModel.selectedFileIDs.insert(file.id)
                if let anchor = viewModel.selectedFileID {
                    viewModel.selectedFileIDs.insert(anchor)
                }
            }
            viewModel.selectedFileID = file.id
            onPhotoSelected(file)
        } else if flags.contains(.shift), let anchorID = viewModel.selectedFileID {
            let ids = ratedFiles.map(\.id)
            if let from = ids.firstIndex(of: anchorID),
               let to = ids.firstIndex(of: file.id) {
                let range = from <= to ? from ... to : to ... from
                viewModel.selectedFileIDs = Set(ids[range])
            }
        } else {
            viewModel.selectedFileIDs = []
            viewModel.selectedFileID = file.id
            onPhotoSelected(file)
        }
    }

    private func handleDoubleSelect(for file: FileItem) {
        viewModel.selectedFileID = file.id
        viewModel.zoomOverlayVisible = true
    }
}
