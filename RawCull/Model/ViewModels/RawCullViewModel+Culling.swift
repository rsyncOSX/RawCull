//
//  RawCullViewModel+Culling.swift
//  RawCull
//

extension RawCullViewModel {
    func extractRatedfilenames(_ rating: Int) -> [String] {
        filteredFiles
            .filter { getRating(for: $0) >= rating }
            .map(\.name)
    }

    func extractTaggedfilenames() -> [String] {
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
              let taggedfilerecords = cullingModel.savedFiles[index].filerecords
        else { return [] }
        return taggedfilerecords.compactMap(\.fileName)
    }

    func getRating(for file: FileItem) -> Int {
        guard let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource?.url }),
              let filerecords = cullingModel.savedFiles[index].filerecords,
              let record = filerecords.first(where: { $0.fileName == file.name })
        else { return 0 }
        return record.rating ?? 0
    }

    func updateRating(for file: FileItem, rating: Int) {
        Task {
            guard let selectedSource else { return }
            if let index = cullingModel.savedFiles.firstIndex(where: { $0.catalog == selectedSource.url }),
               let recordIndex = cullingModel.savedFiles[index].filerecords?.firstIndex(where: { $0.fileName == file.name }) {
                cullingModel.savedFiles[index].filerecords?[recordIndex].rating = rating
                await WriteSavedFilesJSON(cullingModel.savedFiles)
            }
        }
    }

    func toggleTag(for file: FileItem) async {
        await cullingModel.toggleSelectionSavedFiles(
            in: file.url,
            toggledfilename: file.name,
        )
    }
}
