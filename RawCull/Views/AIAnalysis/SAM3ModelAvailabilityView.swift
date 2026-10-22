import SwiftUI

struct SAM3ModelAvailabilityView: View {
    let status: RawCullAICapabilityStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Validating local model…")
                    .foregroundStyle(.secondary)

            case .available:
                Label("Model ready: SAM 3", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .missing:
                Label("Download SAM 3 in Settings › AI.", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)

            case let .invalid(_, reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)

            case let .unavailable(reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }
}
