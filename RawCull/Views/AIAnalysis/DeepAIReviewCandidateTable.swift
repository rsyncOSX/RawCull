import SwiftUI

struct DeepAIReviewCandidateTable: View {
    let candidates: [DeepAIReviewCandidate]
    let winnerID: UUID?
    @Binding var selection: UUID?

    var body: some View {
        Table(candidates, selection: $selection) {
            TableColumn("Done") { candidate in
                Image(systemName: candidate.isCompleted ? "checkmark.circle.fill" : "ellipsis.circle")
                    .foregroundStyle(candidate.isCompleted ? Color.green : Color.secondary)
                    .accessibilityLabel(candidate.isCompleted ? "Completed" : "Waiting")
            }
            .width(45)
            TableColumn("Rank") { candidate in
                Text("#\(candidate.rank)")
                    .monospacedDigit()
            }
            .width(45)
            TableColumn("File") { candidate in
                Text(candidate.fileName)
                    .lineLimit(1)
            }
            TableColumn("Deep") { candidate in
                Text(score(candidate.deepScore))
                    .monospacedDigit()
            }
            TableColumn("Sharp") { candidate in
                Text(score(candidate.normalSharpnessScore))
                    .monospacedDigit()
            }
            TableColumn("Prompt") { candidate in
                Text(promptTitle(candidate))
                    .lineLimit(1)
            }
            TableColumn("Prompt mask") { candidate in
                Text(maskStatus(candidate))
                    .foregroundStyle(maskStatusColor(candidate.requestedPromptObtained))
            }
            TableColumn("AF") { candidate in
                Text(candidate.autofocusInsideMask.map { $0 ? "In" : "Out" } ?? "—")
            }
            TableColumn("Cover") { candidate in
                Text(percent(candidate.maskCoverage))
                    .monospacedDigit()
            }
            TableColumn("Notes") { candidate in
                Text(notes(candidate))
                    .foregroundStyle(candidate.issues.isEmpty ? Color.secondary : Color.orange)
                    .lineLimit(2)
            }
        }
        .aiAnalysisTableNavigation(ids: candidates.map(\.fileID), selection: $selection)
    }

    private func score(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(3)))
    }

    private func percent(_ value: Float?) -> String {
        guard let value, value.isFinite else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func promptTitle(_ candidate: DeepAIReviewCandidate) -> String {
        guard let prompt = candidate.maskPromptUsed else { return "—" }
        let title = switch prompt {
        case .subject: "Subject"
        case .person: "Person"
        case .bird: "Bird"
        case .deer: "Deer"
        case .animal: "Animal"
        case .car: "Car"
        case .birdHead: "Bird Head"
        case .animalHead: "Animal Head"
        case .face: "Face"
        }
        return candidate.usedFallbackMask ? "\(title) fallback" : title
    }

    private func maskStatus(_ candidate: DeepAIReviewCandidate) -> String {
        guard let verified = candidate.requestedPromptObtained else { return "—" }
        return verified ? "Obtained" : "Check"
    }

    private func maskStatusColor(_ verified: Bool?) -> Color {
        switch verified {
        case true: .green
        case false: .orange
        case nil: .secondary
        }
    }

    private func notes(_ candidate: DeepAIReviewCandidate) -> String {
        if candidate.fileID == winnerID, candidate.issues.isEmpty {
            return "Recommended"
        }
        return candidate.issues.map(issueTitle).joined(separator: " · ")
    }
}

private func issueTitle(_ issue: DeepAIReviewCandidateIssue) -> String {
    switch issue {
    case .imageDecodeFailed: "Image could not be decoded"
    case .maskUnavailable: "No subject mask"
    case let .maskAcquisitionFailed(reason): "Mask failed: \(reason)"
    case .poorMaskQuality: "Mask quality is poor"
    case .specificPromptNotFound: "Specific prompt not found"
    case .subjectDetailUnavailable: "Subject detail unavailable"
    case .noReliableLocalPatch: "No reliable local patch"
    case .backgroundDetailDominated: "Background detail dominated"
    }
}
