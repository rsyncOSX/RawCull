import OSLog
import SwiftUI

struct BurstNextUpCard: View {
    let resultsAreAvailable: Bool
    let fileCount: Int
    let completedCount: Int
    let groupCount: Int
    let controlsAreBusy: Bool
    let catalogPreparation: BurstCatalogPreparationPresentation
    let analyzeBursts: () -> Void
    let openNeedsReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Next up")
                .font(.headline)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    actionContent.frame(minWidth: 380, maxWidth: .infinity, alignment: .leading)
                    progressRing
                }
                VStack(alignment: .leading, spacing: 24) {
                    actionContent
                    progressRing.frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.65), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private var actionContent: some View {
        HStack(spacing: 20) {
            Image(systemName: resultsAreAvailable ? "photo.stack.fill" : "photo.on.rectangle.angled")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
                .frame(width: 64)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                // Both states participate in layout so completion only changes the text.
                ZStack(alignment: .leading) {
                    Text("Start by finding burst groups")
                        .opacity(resultsAreAvailable ? 0 : 1)
                        .accessibilityHidden(resultsAreAvailable)
                    Text("Continue reviewing your bursts")
                        .opacity(resultsAreAvailable ? 1 : 0)
                        .accessibilityHidden(!resultsAreAvailable)
                }
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .leading) {
                    Text("We’ll cluster visually similar photos so you can compare them side by side.")
                        .opacity(resultsAreAvailable ? 0 : 1)
                        .accessibilityHidden(resultsAreAvailable)
                    Text("Compare each sequence side by side and keep the strongest frames.")
                        .opacity(resultsAreAvailable ? 1 : 0)
                        .accessibilityHidden(!resultsAreAvailable)
                }
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        Label("\(fileCount) photos", systemImage: "clock")
                        Text("·")
                        preparationStatus
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(fileCount) photos", systemImage: "clock")
                        preparationStatus
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Button(action: resultsAreAvailable ? openNeedsReview : analyzeBursts) {
                    Label(
                        resultsAreAvailable ? "Open Review Queue" : "Find Burst Groups",
                        systemImage: resultsAreAvailable ? "arrow.right" : "waveform.path.ecg",
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(controlsAreBusy || fileCount == 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var preparationStatus: some View {
        ZStack(alignment: .leading) {
            Text(resultsAreAvailable ? "Ready to review" : "About a minute")
                .opacity(catalogPreparation.isRunning ? 0 : 1)
                .accessibilityHidden(catalogPreparation.isRunning)
            HStack(spacing: 6) {
                ProgressView(value: catalogPreparation.overallCompletionFraction)
                    .frame(width: 48)
                Text(catalogPreparationStatus).lineLimit(1)
            }
            .opacity(catalogPreparation.isRunning ? 1 : 0)
            .accessibilityHidden(!catalogPreparation.isRunning)
        }
        .frame(width: 190, alignment: .leading)
    }

    private var progressRing: some View {
        BurstReviewProgressRing(
            completedCount: completedCount,
            totalCount: resultsAreAvailable ? groupCount : fileCount,
        )
        .padding(8)
    }

    private var catalogPreparationStatus: LocalizedStringResource {
        switch catalogPreparation.activeStage {
        case .semanticIndex:
            "Indexing photos…"

        case .sharpness:
            "Scoring sharpness…"

        case .burstGroups:
            "Finding burst groups…"

        case nil:
            "Preparing…"
        }
    }
}
