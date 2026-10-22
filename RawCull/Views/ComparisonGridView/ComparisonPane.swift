import RawCullCore
import SwiftUI

struct ComparisonPane: View {
    let viewModel: RawCullViewModel
    let session: ComparisonSessionModel
    let presentation: ComparisonSessionPresentation
    let file: FileItem
    let isSelected: Bool

    private var files: [FileItem] { presentation.files }

    var body: some View {
        let burstAnalysis = presentation.burstComparisonResult
        ComparisonImagePaneView(
            file: file,
            state: presentation.imageStates[file.id],
            focusPoints: focusPoints(for: file),
            viewportState: viewportStateBinding(for: file),
            useThumbnailSource: useThumbnailSourceBinding(for: file),
            isSelected: isSelected,
            rating: ratingDisplay(for: file),
            exifSummary: ExifSummary.make(from: file.exifData),
            saliencyLabel: saliencyLabel(for: file),
            burstAnalysis: burstAnalysis,
            burstCandidate: burstCandidate(for: file, in: burstAnalysis),
            burstRating: viewModel.getRating(for: file),
            sharpnessContext: sharpnessContext(for: file),
            onSelect: { session.select(file.id) },
            onRate: { rating in
                viewModel.updateRatingAndAdvance(for: file, rating: rating, in: files)
            },
            onSourceChange: {
                startReloadImage(for: file)
            },
        )
    }

    private func useThumbnailSourceBinding(for file: FileItem) -> Binding<Bool> {
        Binding(
            get: {
                session.usesThumbnailSource(for: file.id)
            },
            set: { newValue in
                session.setUsesThumbnailSource(newValue, for: file.id)
            },
        )
    }

    private func viewportStateBinding(for file: FileItem) -> Binding<ComparisonViewportInteractionState> {
        Binding(
            get: {
                session.viewportState(for: file.id)
            },
            set: { newValue in
                session.setViewportState(newValue, for: file.id)
            },
        )
    }

    private func startReloadImage(for file: FileItem) {
        Task { await session.reload(file) }
    }

    private func focusPoints(for file: FileItem) -> [FocusPoint]? {
        let points =
            viewModel.focusPoints?
            .filter { $0.sourceFile == file.name }
            .flatMap(\.focusPoints) ?? []
        return points.isEmpty ? nil : points
    }

    private func ratingDisplay(for file: FileItem) -> RatingDisplay {
        RatingDisplay(
            rating: viewModel.getRating(for: file),
            isExplicit: viewModel.taggedNamesCache.contains(file.name),
        )
    }

    private func burstCandidate(
        for file: FileItem,
        in analysis: BurstAnalysisResult?,
    ) -> BurstCandidateScore? {
        guard let analysis,
            analysis.fileIDs.contains(file.id)
        else { return nil }
        return analysis.candidates.first { $0.fileID == file.id }
    }

    private func saliencyLabel(for file: FileItem) -> String? {
        viewModel.sharpnessModel.saliencyInfo[file.id]?.subjectLabel
    }

    private func sharpnessContext(for file: FileItem) -> SharpnessComparisonContext? {
        SharpnessComparisonSummary.context(
            for: file.id,
            fileIDs: files.map(\.id),
            scores: viewModel.sharpnessModel.scores,
            breakdowns: comparisonBreakdowns(),
            winnerID: comparisonWinnerFile()?.id,
        )
    }

    private func comparisonBreakdowns() -> [FileItem.ID: SharpnessBreakdown] {
        Dictionary(
            uniqueKeysWithValues: files.compactMap { file in
                guard
                    let breakdown = presentation.imageStates[file.id]?.sharpnessBreakdown
                        ?? viewModel.sharpnessModel.breakdowns[file.id]
                else { return nil }
                return (file.id, breakdown)
            })
    }

    private func comparisonWinnerFile() -> FileItem? {
        if let manual = viewModel.manualOverrideWinner(in: files)?.file {
            return manual
        }
        guard let winnerID = presentation.burstComparisonResult?.recommendedFileID else { return nil }
        return files.first { $0.id == winnerID }
    }
}
