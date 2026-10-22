import SwiftUI

struct AIModelLicenceMetadataView: View {
    let descriptor: RawCullAIModelDownloadDescriptor

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                Text("Publisher")
                    .foregroundStyle(.secondary)
                Text(descriptor.publisher)
                    .textSelection(.enabled)
            }
            GridRow {
                Text("Model version")
                    .foregroundStyle(.secondary)
                Text(descriptor.modelVersion)
                    .textSelection(.enabled)
            }
            GridRow {
                Text("Licence")
                    .foregroundStyle(.secondary)
                Text(descriptor.licence.name)
                    .textSelection(.enabled)
            }
            if let revision = descriptor.upstreamRevision {
                GridRow {
                    Text("Upstream revision")
                        .foregroundStyle(.secondary)
                    Text(revision)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
            }
        }
        .font(.caption)
    }
}
