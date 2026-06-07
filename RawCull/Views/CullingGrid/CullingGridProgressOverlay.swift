import SwiftUI

struct CullingGridProgressOverlay: View {
    @Bindable var viewModel: RawCullViewModel

    var body: some View {
        Group {
            if viewModel.sharpnessModel.isScoring {
                ProgressCount(
                    progress: Binding(
                        get: { Double(viewModel.sharpnessModel.scoringProgress) },
                        set: { _ in },
                    ),
                    estimatedSeconds: Binding(
                        get: { viewModel.sharpnessModel.scoringEstimatedSeconds },
                        set: { _ in },
                    ),
                    max: Double(viewModel.sharpnessModel.scoringTotal),
                    statusText: "Scoring sharpness...",
                )
                .frame(maxWidth: 480)
                .progressOverlayStyle()
            }

            if viewModel.similarityModel.isGrouping || indeterminateBurstAnalysisRunning {
                HStack(spacing: 10) {
                    ProgressView()
                        .fixedSize()
                    Text(viewModel.burstAnalysisProgress.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .progressOverlayStyle()
            }

            if viewModel.similarityModel.isIndexing {
                ProgressCount(
                    progress: Binding(
                        get: { Double(viewModel.similarityModel.indexingProgress) },
                        set: { _ in },
                    ),
                    estimatedSeconds: Binding(
                        get: { viewModel.similarityModel.indexingEstimatedSeconds },
                        set: { _ in },
                    ),
                    max: Double(viewModel.similarityModel.indexingTotal),
                    statusText: "Indexing similarity...",
                )
                .frame(maxWidth: 480)
                .progressOverlayStyle()
            }
        }
    }

    private var indeterminateBurstAnalysisRunning: Bool {
        viewModel.burstAnalysisProgress.isRunning && !viewModel.burstAnalysisProgress.isCountBased
    }
}

private extension View {
    func progressOverlayStyle() -> some View {
        padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1),
            )
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
    }
}
