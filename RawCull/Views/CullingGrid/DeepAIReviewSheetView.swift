import PhotoAIContracts
import SwiftUI

struct DeepAIReviewSheetView: View {
    @Bindable var feature: DeepAIReviewFeature
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let files: [FileItem]
    let onRun: () -> Void
    let onCancel: () -> Void
    let onApply: (DeepAIReviewResult) -> Void
    let onClose: () -> Void

    private var result: DeepAIReviewResult? {
        feature.result(for: groupSignature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeepAIReviewSheetControls(
                feature: feature,
                canRun: !files.isEmpty && feature.availability.isAvailable,
                canApply: result?.recommendedFileID != nil,
                onRun: onRun,
                onCancel: onCancel,
                onApply: {
                    if let result { onApply(result) }
                },
                onClose: onClose,
            )

            Divider()

            DeepAIReviewSheetContent(
                state: feature.state,
                result: result,
                groupID: groupID,
            )
        }
        .padding(16)
        .frame(minWidth: 1_080, idealWidth: 1_220, minHeight: 520, idealHeight: 640)
        .interactiveDismissDisabled(feature.isRunning)
    }
}

private struct DeepAIReviewSheetControls: View {
    @Bindable var feature: DeepAIReviewFeature
    let canRun: Bool
    let canApply: Bool
    let onRun: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Review target", selection: $feature.preset) {
                Text("Auto").tag(DeepAIReviewPreset.auto)
                Text("Full Subject").tag(DeepAIReviewPreset.fullSubject)
                Text("Head / Face").tag(DeepAIReviewPreset.headFace)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .disabled(feature.isRunning)

            if feature.isRunning {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
            } else {
                Button("Run Deep Review", systemImage: "sparkle.magnifyingglass", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
            }

            Spacer()

            Button("Mark Winner & Close", systemImage: "checkmark.circle", action: onApply)
                .buttonStyle(.borderedProminent)
                .disabled(!canApply || feature.isRunning)

            Button("Close", systemImage: "xmark", action: onClose)
                .buttonStyle(.bordered)
                .disabled(feature.isRunning)
        }
    }
}

private struct DeepAIReviewSheetContent: View {
    let state: DeepAIReviewState
    let result: DeepAIReviewResult?
    let groupID: Int

    var body: some View {
        if let result {
            DeepAIReviewSummaryView(result: result)
            DeepAIReviewCandidateTable(candidates: result.candidates, winnerID: result.recommendedFileID)
        } else {
            switch state {
            case let .preparing(activeGroupID, totalCount) where activeGroupID == groupID:
                DeepAIReviewProgressHeader(
                    completedCount: 0,
                    totalCount: totalCount,
                    currentFileName: nil,
                )
                Spacer()

            case let .running(progress) where progress.groupID == groupID:
                DeepAIReviewProgressHeader(
                    completedCount: progress.completedCount,
                    totalCount: progress.totalCount,
                    currentFileName: progress.currentFileName,
                )
                DeepAIReviewCandidateTable(candidates: progress.candidates, winnerID: nil)

            case let .completing(activeGroupID) where activeGroupID == groupID:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Completing Deep Review…")
                        .font(.headline)
                }
                Spacer()

            case let .failed(activeGroupID, failure) where activeGroupID == nil || activeGroupID == groupID:
                ContentUnavailableView(
                    "Deep Review Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failureMessage(failure)),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .idle, .preparing, .running, .completing, .failed, .completed:
                ContentUnavailableView(
                    "No Deep Review Yet",
                    systemImage: "sparkle.magnifyingglass",
                    description: Text("Run SAM 3 subject-detail analysis for this burst group."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func failureMessage(_ failure: DeepAIReviewFailure) -> String {
        switch failure {
        case let .modelUnavailable(reason):
            reason
        case .noCandidates:
            "This burst group has no candidates to review."
        case let .pipelineFailed(reason):
            "The in-process SAM 3 pipeline failed: \(reason)"
        }
    }
}

private struct DeepAIReviewProgressHeader: View {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Deep reviewing subject detail")
                    .font(.headline)
                Spacer()
                Text("\(completedCount) of \(totalCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(completedCount), total: Double(max(totalCount, 1)))
            if let currentFileName {
                Text("Analyzing \(currentFileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct DeepAIReviewSummaryView: View {
    let result: DeepAIReviewResult

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(recommendationLabel)
                    .font(.headline)
                Text(confidenceTitle)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(confidenceColor.opacity(0.16), in: Capsule())
                    .foregroundStyle(confidenceColor)
                Text(presetTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !explanation.isEmpty {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var recommendationLabel: String {
        guard let candidate = result.recommendedCandidate else {
            return "No reliable winner"
        }
        return "Deep Review recommends frame \(candidate.rank)"
    }

    private var confidenceTitle: LocalizedStringResource {
        switch result.confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }

    private var presetTitle: LocalizedStringResource {
        switch result.preset {
        case .auto: "Auto"
        case .fullSubject: "Full Subject"
        case .headFace: "Head / Face"
        }
    }

    private var confidenceColor: Color {
        switch result.confidence {
        case .high: .green
        case .medium: .orange
        case .low: .gray
        }
    }

    private var explanation: String {
        let reasons = result.reasons.map(reasonTitle)
        let cautions = result.cautions.map(issueTitle)
        return (reasons + cautions).prefix(4).joined(separator: " · ")
    }
}

private struct DeepAIReviewCandidateTable: View {
    let candidates: [DeepAIReviewCandidate]
    let winnerID: UUID?

    var body: some View {
        Table(candidates) {
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
            TableColumn("Mask") { candidate in
                Text(maskStatus(candidate))
                    .foregroundStyle(maskStatusColor(candidate.promptVerified))
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
        let title: String = switch prompt {
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
        guard let verified = candidate.promptVerified else { return "—" }
        return verified ? "Matched" : "Check"
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

private func reasonTitle(_ reason: DeepAIReviewReason) -> String {
    switch reason {
    case .strongestSubjectDetail: "Strongest subject detail"
    case .autofocusInsideSubject: "AF point inside subject"
    case .localDetailEvidence: "Local detail evidence"
    case .requestedPromptMatched: "Requested prompt matched"
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
