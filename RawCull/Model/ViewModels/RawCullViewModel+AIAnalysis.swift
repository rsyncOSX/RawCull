import Foundation

nonisolated enum AIAnalysisInputSource: String, CaseIterable, Identifiable, Sendable {
    case gridSelection
    case taggedImages

    var id: String {
        rawValue
    }
}

extension RawCullViewModel {
    func aiAnalysisFiles(for source: AIAnalysisInputSource) -> [FileItem] {
        switch source {
        case .gridSelection:
            var selectedIDs = selectedFileIDs
            if selectedIDs.isEmpty, let selectedFileID {
                selectedIDs.insert(selectedFileID)
            }
            return filteredFiles.filter { selectedIDs.contains($0.id) }

        case .taggedImages:
            let taggedNames = Set(extractTaggedfilenames())
            return files.filter { taggedNames.contains($0.name) }
        }
    }
}
