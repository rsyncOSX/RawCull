import Foundation
@testable import RawCull
import RawCullCore
import Testing

private func makeComparisonDisplayFile(_ name: String, id: UUID) -> FileItem {
    FileItem(
        id: id,
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: 0),
        exifData: nil,
        afFocusNormalized: nil,
    )
}

private func makeComparisonBurstResult(
    groupID: Int,
    fileIDs: [FileItem.ID],
    recommendedFileID: FileItem.ID? = nil,
    secondBestFileID: FileItem.ID? = nil,
) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: groupID,
        fileIDs: fileIDs,
        candidates: [],
        recommendedFileID: recommendedFileID,
        secondBestFileID: secondBestFileID,
        confidence: .medium,
        reviewState: .algorithmReviewed,
        isSafeForOneClickCulling: true,
        reasons: [],
        cautions: [],
    )
}

@MainActor
@Suite("ComparisonGridDisplayState")
struct ComparisonGridDisplayStateTests {
    private let ids = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
    ]

    @Test(.tags(.smoke))
    func `load key ignores selection changes`() {
        let files = makeFiles()
        let firstState = makeState(filteredFiles: files, selectedFileID: ids[0])
        let secondState = makeState(filteredFiles: files, selectedFileID: ids[2])

        #expect(firstState.loadKey == secondState.loadKey)
        #expect(firstState.selectedComparisonFile?.id == ids[0])
        #expect(secondState.selectedComparisonFile?.id == ids[2])
    }

    @Test(.tags(.smoke))
    func `files resolve displayed comparison IDs in order`() {
        let files = makeFiles().reversed()
        let state = makeState(filteredFiles: Array(files), comparisonFileIDs: [
            ids[2],
            ids[0],
            UUID(uuidString: "00000000-0000-0000-0000-000000009999")!,
            ids[4],
            ids[1],
        ])

        #expect(state.files.map(\.id) == [ids[2], ids[0], ids[4]])
        #expect(state.comparisonDisplayFileIDs == [
            ids[2],
            ids[0],
            UUID(uuidString: "00000000-0000-0000-0000-000000009999")!,
            ids[4],
        ])
        #expect(state.allComparisonFiles.map(\.id) == [ids[2], ids[0], ids[4]])
    }

    @Test(.tags(.smoke))
    func `finalist focus uses recommended and second best IDs`() {
        let files = makeFiles()
        let result = makeComparisonBurstResult(
            groupID: 7,
            fileIDs: ids,
            recommendedFileID: ids[3],
            secondBestFileID: ids[1],
        )
        let state = makeState(
            filteredFiles: files,
            activeBurstComparisonGroupID: 7,
            finalistFocusActive: true,
            burstResults: [7: result],
        )

        #expect(state.files.map(\.id) == [ids[3], ids[1]])
        #expect(state.comparisonDisplayFileIDs == [ids[3], ids[1]])
    }

    @Test(.tags(.smoke))
    func `finalist focus falls back to first four comparison IDs without burst result`() {
        let files = makeFiles()
        let state = makeState(
            filteredFiles: files,
            activeBurstComparisonGroupID: 7,
            finalistFocusActive: true,
        )

        #expect(state.files.map(\.id) == Array(ids.prefix(4)))
        #expect(state.comparisonDisplayFileIDs == Array(ids.prefix(4)))
    }

    @Test(.tags(.smoke))
    func `selected comparison file is nil outside displayed files`() {
        let files = makeFiles()
        let state = makeState(filteredFiles: files, selectedFileID: ids[4])

        #expect(state.files.map(\.id) == Array(ids.prefix(4)))
        #expect(state.selectedComparisonFile == nil)
    }

    private func makeFiles() -> [FileItem] {
        ids.enumerated().map { index, id in
            makeComparisonDisplayFile("display-\(index).ARW", id: id)
        }
    }

    private func makeState(
        filteredFiles: [FileItem],
        comparisonFileIDs: [FileItem.ID]? = nil,
        selectedFileID: FileItem.ID? = nil,
        activeBurstComparisonGroupID: Int? = nil,
        finalistFocusActive: Bool = false,
        burstResults: [Int: BurstAnalysisResult] = [:],
    ) -> ComparisonGridDisplayState {
        ComparisonGridDisplayState(
            filteredFiles: filteredFiles,
            comparisonFileIDs: comparisonFileIDs ?? ids,
            selectedFileID: selectedFileID,
            activeBurstComparisonGroupID: activeBurstComparisonGroupID,
            finalistFocusActive: finalistFocusActive,
            burstAnalysisResult: { burstResults[$0] },
        )
    }
}
