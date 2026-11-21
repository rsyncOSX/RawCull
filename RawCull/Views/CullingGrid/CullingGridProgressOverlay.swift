import SwiftUI

struct CullingGridProgressOverlay: View {
    @Environment(BurstWorkflowController.self) private var burstWorkflow
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    let similarityFeature: RawCullSimilarityFeature

    var body: some View {
        ZStack {
            progressContent
        }
        .animation(.easeInOut(duration: 0.2), value: sharpnessModel.isScoring)
        .animation(.easeInOut(duration: 0.2), value: similarityFeature.indexing.isIndexing)
        .animation(.easeInOut(duration: 0.2), value: similarityFeature.isGrouping)
    }

    @ViewBuilder
    private var progressContent: some View {
        if sharpnessModel.isScoring {
            ProgressCount(
                completed: sharpnessModel.scoringProgress,
                total: sharpnessModel.scoringTotal,
                estimatedSeconds: sharpnessModel.scoringEstimatedSeconds,
                statusText: "Scoring sharpness...",
            )
            .frame(maxWidth: 480)
            .progressOverlayStyle()
        }

        if similarityFeature.isGrouping || indeterminateBurstAnalysisRunning {
            HStack(spacing: 10) {
                ProgressView()
                    .fixedSize()
                Text(burstWorkflow.burstAnalysisProgress.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            .progressOverlayStyle()
        }

        if similarityFeature.indexing.isIndexing {
            ProgressCount(
                completed: similarityFeature.indexing.completed,
                total: similarityFeature.indexing.total,
                estimatedSeconds: similarityFeature.indexing.estimatedSeconds,
                statusText: "Indexing similarity...",
            )
            .frame(maxWidth: 480)
            .progressOverlayStyle()
        }
    }

    private var indeterminateBurstAnalysisRunning: Bool {
        burstWorkflow.burstAnalysisProgress.isRunning && !burstWorkflow.burstAnalysisProgress.isCountBased
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
