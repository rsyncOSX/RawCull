import SwiftUI

struct ObjectPhotoAssessmentSection: View {
    let assessment: ObjectPhotoAssessment
    let selectedObjectID: String?
    let selectedEvidence: ObjectFocusSpatialEvidence?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let summary = assessment.imageSummary {
                Text(summary).font(.body)
            }
            Text("Qwen model confidence: \(assessment.confidence.formatted(.percent.precision(.fractionLength(0))))")
                .font(.caption)
            if let object = assessment.objects.first(where: { $0.id == selectedObjectID }) {
                ObjectAssessmentDetail(object: object)
            }
            if let evidence = selectedEvidence {
                ObjectFocusEvidenceDetail(evidence: evidence)
            }
            ForEach(assessment.relationships, id: \.self) { relationship in
                Text("Relationship: \(relationship)").font(.caption)
            }
            AIAnalysisFindingsSection(
                title: "Strengths", values: assessment.strengths,
                icon: "checkmark.circle", color: .green,
            )
            AIAnalysisFindingsSection(
                title: "Issues", values: assessment.problems,
                icon: "exclamationmark.triangle", color: .orange,
            )
            if !assessment.preferredObjectIDs.isEmpty {
                Text("Preferred objects: \(assessment.preferredObjectIDs.joined(separator: ", "))")
            }
        }
    }
}
