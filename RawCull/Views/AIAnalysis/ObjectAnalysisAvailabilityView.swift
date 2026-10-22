import AppKit
import SwiftUI

struct ObjectAnalysisAvailabilityView: View {
    let availability: ObjectAnalysisAvailability

    var body: some View {
        HStack {
            switch availability {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking local SAM 3 and Qwen models…")

            case .ready:
                Label("Models ready: SAM 3 and Qwen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .sam3Unavailable:
                Label("Install SAM 3 in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)

            case .qwenUnavailable:
                Label("Install Qwen in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)

            case .bothUnavailable:
                Label("Install SAM 3 and Qwen in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
    }
}
