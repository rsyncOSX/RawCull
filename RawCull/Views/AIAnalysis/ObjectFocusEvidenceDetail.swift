import AppKit
import SwiftUI

struct ObjectFocusEvidenceDetail: View {
    let evidence: ObjectFocusSpatialEvidence

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Measured focus locations").font(.headline)
            Text(
                "Camera AF point: \(evidence.autofocusInsideObject.map { $0 ? "inside this object" : "outside this object" } ?? "unavailable")",
            )
            if let share = evidence.focusMapShare {
                Text(
                    "Highlighted focus-map edges on this object: \(share.formatted(.percent.precision(.fractionLength(0)))) of all highlighted edges",
                )
            } else {
                Text("Focus map: unavailable")
            }
            if let near = evidence.focusMapNearAutofocus {
                Text("Highlighted edges near AF point: \(near ? "yes" : "no")")
            }
            Text("These locations support focus review; overlap alone does not confirm sharpness.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
