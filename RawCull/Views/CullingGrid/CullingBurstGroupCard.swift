import SwiftUI

struct CullingBurstGroupCard: View {
    let viewModel: RawCullViewModel
    let group: CullingGridVisibleBurstGroup
    let number: Int
    let select: (FileItem) -> Void
    let markBurstGroupReviewed: (Int) -> Void
    let deferBurstGroup: (Int) -> Void

    var body: some View {
        let analysis = viewModel.burstAnalysisResult(for: group.id)

        return VStack(alignment: .leading, spacing: 0) {
            if group.id == -1 || group.files.count > 1 {
                BurstGroupHeaderView(
                    groupNumber: number,
                    groupID: group.id,
                    files: group.files,
                    analysis: analysis,
                    onReviewed: markBurstGroupReviewed,
                    onDeferred: deferBurstGroup,
                    viewModel: viewModel,
                )
            }

            Divider()
            ScrollView(.horizontal) {
                // An eager stack gives the horizontal scroll view a stable intrinsic
                // height while its card is hosted in the outer LazyVStack. A nested
                // LazyHStack can remain unrealized and collapse the row to its header.
                HStack(spacing: 12) {
                    ForEach(group.files, id: \.id) { file in
                        CullingGridThumbnail(
                            viewModel: viewModel, file: file, doubleSelectActionName: "Open burst",
                            onSelect: { select(file) },
                            onDoubleSelect: { viewModel.compareBurstGroup(group.files) },
                        )
                        .id(file.id)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(.quaternary.opacity(0.45), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.separator.opacity(0.55), lineWidth: 1)
        }
    }
}
