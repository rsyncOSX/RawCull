import Foundation
import RawCullCore

struct ComparisonGridDisplayState {
    let files: [FileItem]
    let allComparisonFiles: [FileItem]
    let selectedComparisonFile: FileItem?
    let burstComparisonResult: BurstAnalysisResult?
    let comparisonDisplayFileIDs: [FileItem.ID]

    init(
        filteredFiles: [FileItem],
        comparisonFileIDs: [FileItem.ID],
        selectedFileID: FileItem.ID?,
        activeBurstComparisonGroupID: Int?,
        finalistFocusActive: Bool,
        burstAnalysisResult: (Int) -> BurstAnalysisResult?,
    ) {
        if let activeBurstComparisonGroupID {
            burstComparisonResult = burstAnalysisResult(activeBurstComparisonGroupID)
        } else {
            burstComparisonResult = nil
        }

        if finalistFocusActive {
            let finalistIDs = ComparisonFinalistFocus.focusedIDs(from: burstComparisonResult)
            comparisonDisplayFileIDs = finalistIDs.isEmpty ? Array(comparisonFileIDs.prefix(4)) : finalistIDs
        } else {
            comparisonDisplayFileIDs = Array(comparisonFileIDs.prefix(4))
        }

        let filesByID = Dictionary(uniqueKeysWithValues: filteredFiles.map { ($0.id, $0) })
        let resolvedFiles = comparisonDisplayFileIDs.compactMap { filesByID[$0] }
        files = resolvedFiles
        allComparisonFiles = comparisonFileIDs.prefix(4).compactMap { filesByID[$0] }
        selectedComparisonFile = selectedFileID.flatMap { id in
            resolvedFiles.first { $0.id == id }
        }
    }

    var loadKey: String {
        files.map(\.id.uuidString).joined(separator: ",")
    }
}
