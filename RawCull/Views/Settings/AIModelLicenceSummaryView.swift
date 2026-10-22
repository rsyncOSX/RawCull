import SwiftUI

struct AIModelLicenceSummaryView: View {
    let descriptor: RawCullAIModelDownloadDescriptor
    let licenceAccepted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Licence:")
                    .font(.caption.weight(.medium))

                Text(descriptor.licence.name)
                    .font(.caption)

                if licenceAccepted {
                    Label("Accepted", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            Text(descriptor.licence.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(descriptor.displayName) licence")
        .accessibilityValue("\(descriptor.licence.name). \(licenceAccepted ? "Accepted" : "Not accepted"). \(descriptor.licence.summary)")
    }
}
