import SwiftUI

struct ObjectInstanceList: View {
    let instances: [ObjectInstanceDescriptor]
    let spatialEvidence: [String: ObjectFocusSpatialEvidence]
    @Binding var selectedObjectID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Objects").font(.headline)
            ForEach(instances) { object in
                Button {
                    selectedObjectID = object.id
                } label: {
                    HStack {
                        Text("\(object.id). \(object.concept)")
                        if !object.aliases.isEmpty {
                            Text("(\(object.aliases.joined(separator: ", ")))")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let evidence = spatialEvidence[object.id] {
                            Text(evidence.autofocusInsideObject.map { $0 ? "AF inside" : "AF outside" } ?? "AF unavailable")
                                .foregroundStyle(.secondary)
                            if let share = evidence.focusMapShare {
                                Text("Focus map \(share.formatted(.percent.precision(.fractionLength(0))))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("SAM 3 mask: \(object.score.formatted(.percent.precision(.fractionLength(0))))")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Object \(object.id), \(object.concept)")
                .accessibilityValue("SAM 3 mask score \(object.score.formatted(.percent))")
            }
        }
    }
}
