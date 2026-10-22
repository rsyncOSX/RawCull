import SwiftUI

struct AIModelDownloadProgressView: View {
    let state: RawCullAIModelDownloadState

    var body: some View {
        switch state {
        case let .downloading(progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Model download progress")
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))

        case .checking, .validating, .removing:
            ProgressView(state.activityTitle)
                .controlSize(.small)
                .accessibilityLabel("Model download status")
                .accessibilityValue(Text(state.activityTitle))

        case .unavailable, .licenceRequired, .notConfigured, .ready,
             .installed, .failed:
            EmptyView()
        }
    }
}
