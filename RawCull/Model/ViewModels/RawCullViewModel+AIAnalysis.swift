import Foundation

nonisolated enum AIAnalysisInputSource: String, CaseIterable, Identifiable, Sendable {
    case gridSelection
    case taggedImages

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .gridSelection: "Grid Selection"
        case .taggedImages: "Tagged Images"
        }
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

    func selectAIAnalysisRecommendation(_ result: DeepAIReviewResult) {
        guard let recommendedFileID = result.recommendedFileID,
              files.contains(where: { $0.id == recommendedFileID })
        else { return }
        selectedFileID = recommendedFileID
        selectedFileIDs = [recommendedFileID]
    }
}
