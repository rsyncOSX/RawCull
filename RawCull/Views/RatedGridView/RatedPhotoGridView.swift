import AppKit
import SwiftUI

struct RatedPhotoGridView: View {
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(SelectionModel.self) private var selection
    @Environment(RatingsModel.self) private var ratings
    @Environment(WorkspaceNavigationModel.self) private var navigation
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
                        RatedImageItemView(file: file,
                            catalogURL: catalogURL,
                            isSelected: selection.selectedFileID == file.id,
                            isMultiSelected: selection.selectedFileIDs.contains(file.id),
                            onSelected: { handleToggleSelection(for: file) },
                            onDoubleSelected: { handleDoubleSelect(for: file) },
                        )
                        .id(file.id)
                    }
                }
                .padding()
            }
            .onChange(of: selection.selectedFileID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
        .task(id: catalogURL) {
            selection.selectedFileIDs = []
        }
        .thumbnailKeyNavigation(axis: .grid) { ratedFiles }
    }

    var cullingModel: CullingModel {
        ratings.cullingModel
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
            uniqueKeysWithValues: catalog.filteredFiles.map { ($0.name, $0) },
        )
        return names.compactMap { byName[$0] }
    }

    private func handleToggleSelection(for file: FileItem) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.selectedFileIDs.contains(file.id) {
                selection.selectedFileIDs.remove(file.id)
            } else {
                selection.selectedFileIDs.insert(file.id)
                if let anchor = selection.selectedFileID {
                    selection.selectedFileIDs.insert(anchor)
                }
            }
            selection.selectedFileID = file.id
            onPhotoSelected(file)
        } else if flags.contains(.shift), let anchorID = selection.selectedFileID {
            let ids = ratedFiles.map(\.id)
            if let from = ids.firstIndex(of: anchorID),
               let to = ids.firstIndex(of: file.id) {
                let range = from <= to ? from ... to : to ... from
                selection.selectedFileIDs = Set(ids[range])
            }
        } else {
            selection.selectedFileIDs = []
            selection.selectedFileID = file.id
            onPhotoSelected(file)
        }
    }

    private func handleDoubleSelect(for file: FileItem) {
        selection.selectedFileID = file.id
        navigation.openZoomOverlay(navigationIDs: ratedFiles.map(\.id))
    }
}
