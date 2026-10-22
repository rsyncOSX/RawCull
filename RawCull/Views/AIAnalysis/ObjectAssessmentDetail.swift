import AppKit
import SwiftUI

struct ObjectAssessmentDetail: View {
    let object: ObjectAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Object \(object.id): \(object.concept)").font(.headline)
            Text(object.description)
            Text("Model judgments — visibility: \(object.visibility.rawValue); focus: \(object.focusQuality.rawValue)")
            if let evidence = object.focusEvidence {
                Text("Focus evidence, crop \(evidence.cropID): \(evidence.observation)")
            }
            Text("Expression: unknown; anatomy unverified")
            Text(
                "Analysis uses a 2048-pixel board of crops from a thumbnail requested at up to 4320 pixels. Preview processing and model input resolution limit detail; RAW recovery is untested.",
            )
            .font(.caption).foregroundStyle(.secondary)
            ForEach(object.obstructions, id: \.self) { Text("Obstruction: \($0)") }
            Label("Strengths", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            if object.strengths.isEmpty {
                Text("None detected").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(Array(object.strengths.enumerated()), id: \.element) { index, strength in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(strength)").font(.caption).foregroundStyle(.secondary)
                    if object.strengthEvidence.indices.contains(index) {
                        let evidence = object.strengthEvidence[index]
                        Text("Crop \(evidence.cropID): \(evidence.observation)").font(.caption)
                    }
                }
            }
            Label("Issues", systemImage: "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            if object.problems.isEmpty {
                Text("None detected").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(Array(object.problems.enumerated()), id: \.element) { index, problem in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(problem)").font(.caption).foregroundStyle(.secondary)
                    if object.problemEvidence.indices.contains(index) {
                        let evidence = object.problemEvidence[index]
                        Text("Crop \(evidence.cropID): \(evidence.observation)").font(.caption)
                    }
                }
            }
        }
    }
}
