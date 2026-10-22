import SwiftUI

struct AIModelDownloadIdentityView: View {
    let descriptor: RawCullAIModelDownloadDescriptor
    let state: RawCullAIModelDownloadState
    let licenceAccepted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(descriptor.displayName)
                    .font(.headline)

                Spacer()

                Label {
                    Text(state.title)
                } icon: {
                    Image(systemName: state.iconName)
                        .accessibilityHidden(true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(state.color)
            }

            Text(descriptor.purpose)
                .font(.callout)

            Text("Publisher: \(descriptor.publisher) · Version: \(descriptor.modelVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let downloadByteCount = descriptor.downloadByteCount {
                Text(
                    "Download size: \(ByteCountFormatter.string(fromByteCount: downloadByteCount, countStyle: .file))",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if case .installed = state {
                Text("Stored and managed by macOS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case let .blocked(reason) = descriptor.releaseReadiness {
                Label {
                    Text(reason)
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                        .accessibilityHidden(true)
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }

            if case let .failed(message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor.displayName)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        var value = RawCullAccessibilityPresentation.modelDownloadValue(
            state: state,
            licenceAccepted: licenceAccepted,
        )
        if let downloadByteCount = descriptor.downloadByteCount {
            value += ". Download size \(ByteCountFormatter.string(fromByteCount: downloadByteCount, countStyle: .file))."
        }
        return value
    }
}
