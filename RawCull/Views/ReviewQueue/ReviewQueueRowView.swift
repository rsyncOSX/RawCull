import SwiftUI

struct ReviewQueueRowView: View {
    let item: ReviewQueueItem
    let onOpen: () -> Void
    let onResolve: () -> Void
    let onIgnore: () -> Void
    let onReopen: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: severityIcon)
                .foregroundStyle(severityColor)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                    Text(item.category.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    if item.resolutionState != .open {
                        Text(item.resolutionState.rawValue.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                if !item.relatedFileNames.isEmpty {
                    Text(item.relatedFileNames.prefix(4).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: onOpen) {
                    Label("Open", systemImage: "arrow.up.forward.square")
                }
                .help(item.recommendedAction)

                if item.resolutionState == .open {
                    Button(action: onResolve) {
                        Label("Resolve", systemImage: "checkmark.circle")
                    }
                    .help("Mark resolved")

                    Button(action: onIgnore) {
                        Label("Ignore", systemImage: "eye.slash")
                    }
                    .help("Ignore this issue")
                } else {
                    Button(action: onReopen) {
                        Label("Reopen", systemImage: "arrow.uturn.backward")
                    }
                    .help("Reopen this issue")
                }
            }
            .labelStyle(.iconOnly)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private var severityIcon: String {
        switch item.severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .blocking: "xmark.octagon"
        }
    }

    private var severityColor: Color {
        switch item.severity {
        case .info: .secondary
        case .warning: .orange
        case .blocking: .red
        }
    }
}
