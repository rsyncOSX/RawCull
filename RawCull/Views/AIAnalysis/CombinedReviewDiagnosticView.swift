import SwiftUI

struct CombinedReviewDiagnosticView: View {
    let feature: CombinedReviewFeature
    let diagnostic: ReviewFailureDiagnostic
    @State private var rejectedText: String?
    @State private var unavailable = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(diagnostic.code.rawValue + " · " + diagnostic.check).font(.caption2).textSelection(.enabled)
            if let path = diagnostic.fieldPath {
                Text("Field: " + path).font(.caption2)
            }
            if let ref = diagnostic.evidenceReference {
                Text("Reference: " + ref.id).font(.caption2).textSelection(.enabled)
            }
            if diagnostic.responseTruncated {
                Text("Rejected text truncated by retention limits.").font(.caption2)
            }
            if diagnostic.retentionUnavailable {
                Text("Rejected text could not be retained; compact diagnostics are preserved.").font(.caption2)
            }
            if let key = diagnostic.rejectedResponseKey {
                DisclosureGroup("Rejected response · untrusted inspection text") {
                    if let rejectedText {
                        Text(rejectedText).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    if unavailable {
                        Text("Rejected text unavailable after cleanup.").font(.caption)
                    }
                    Button("Load rejected text") {
                        Task {
                            let response = await feature.rejectedResponse(key)
                            rejectedText = response?.text
                            unavailable = response == nil
                        }
                    }
                }
            }
        }
    }
}
