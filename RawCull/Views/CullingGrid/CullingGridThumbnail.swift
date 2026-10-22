import SwiftUI

struct CullingGridThumbnail: View {
    let viewModel: RawCullViewModel
    let file: FileItem
    var semanticResultRank: Int?
    var semanticResultCount: Int?
    var semanticResultScore: Float?
    var doubleSelectActionName: LocalizedStringKey = "Open preview"
    let onSelect: () -> Void
    let onDoubleSelect: () -> Void

    var body: some View {
        ImageItemView(
            viewModel: viewModel, file: file,
            isSelected: viewModel.selectedFileID == file.id,
            isMultiSelected: viewModel.selectedFileIDs.contains(file.id),
            thumbnailSize: 200,
            ratingValue: ratingValue(for: file), ratingDisplay: ratingDisplay(for: file),
            ratingColor: ratingColor(for: file),
            semanticResultRank: semanticResultRank, semanticResultCount: semanticResultCount,
            semanticResultScore: semanticResultScore,
            onSelect: onSelect, doubleSelectActionName: doubleSelectActionName,
            onDoubleSelect: onDoubleSelect,
        )
    }

    private func ratingValue(for file: FileItem) -> Int {
        viewModel.getRating(for: file)
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: ratingValue(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func ratingColor(for file: FileItem) -> Color? {
        switch ratingValue(for: file) {
        case -1: .red
        case 2: .yellow
        case 3: .green
        case 4: .blue
        case 5: .purple
        default: nil
        }
    }
}
