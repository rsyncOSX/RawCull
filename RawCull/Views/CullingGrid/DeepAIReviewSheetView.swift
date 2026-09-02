import SwiftUI

struct DeepAIReviewSheetView: View {
    @Bindable var controller: DeepAIReviewController
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let files: [FileItem]
    let onApply: (DeepAIReviewResult) -> Void
    let onClose: () -> Void

    private var result: DeepAIReviewResult? {
        controller.result(for: groupSignature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeepAIReviewSheetControls(
                controller: controller,
                canRun: !files.isEmpty && !controller.isActionUnavailable,
                canApply: result?.recommendedFileID != nil,
                onRun: {
                    Task {
                        await controller.start(for: files)
                    }
                },
                onCancel: controller.cancel,
                onApply: {
                    if let result {
                        onApply(result)
                    }
                },
                onClose: onClose,
            )

            Divider()

            DeepAIReviewSheetContent(
                controller: controller,
                files: files,
                state: controller.presentationState(
                    groupID: groupID,
                    groupSignature: groupSignature,
                ),
            )
        }
        .padding(16)
        .frame(minWidth: 1080, idealWidth: 1220, minHeight: 520, idealHeight: 640)
        .interactiveDismissDisabled(controller.isRunning)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Deep Review")
        .accessibilityValue(RawCullAccessibilityPresentation.deepReviewValue(
            state: controller.presentationState(
                groupID: groupID,
                groupSignature: groupSignature,
            ),
            cachedResult: result,
        ))
    }
}

private struct DeepAIReviewSheetControls: View {
    @Bindable var controller: DeepAIReviewController
    let canRun: Bool
    let canApply: Bool
    let onRun: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker("Review target", selection: $controller.preset) {
                Text("Auto").tag(DeepAIReviewPreset.auto)
                Text("Full Subject").tag(DeepAIReviewPreset.fullSubject)
                Text("Head / Face").tag(DeepAIReviewPreset.headFace)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)
            .disabled(controller.isRunning)
            .accessibilityHint("Selects the subject target used for local detail review.")

            if controller.isRunning {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.bordered)
                    .accessibilityHint("Cancels the active Deep Review.")
            } else {
                Button("Run Deep Review", systemImage: "sparkle.magnifyingglass", action: onRun)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canRun)
                    .accessibilityHint("Runs local AI subject-detail analysis for this burst group.")
            }

            Spacer()

            Button("Mark Winner & Close", systemImage: "checkmark.circle", action: onApply)
                .buttonStyle(.borderedProminent)
                .disabled(!canApply || controller.isRunning)
                .accessibilityHint("Marks the recommended candidate as the manual winner and closes Deep Review.")

            Button("Close", systemImage: "xmark", action: onClose)
                .buttonStyle(.bordered)
                .disabled(controller.isRunning)
                .accessibilityHint("Closes Deep Review without changing the burst winner.")
        }
    }
}

private struct DeepAIReviewSheetContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let state: DeepAIReviewPresentationState

    var body: some View {
        switch state {
        case let .completed(result):
            DeepAIReviewCompletedContent(
                controller: controller,
                files: files,
                result: result,
            )

        case let .preparing(_, totalCount):
            DeepAIReviewProgressHeader(
                completedCount: 0,
                totalCount: totalCount,
                currentFileName: nil,
            )
            Spacer()

        case let .running(progress):
            DeepAIReviewProgressHeader(
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                currentFileName: progress.currentFileName,
            )
            DeepAIReviewCandidateTable(candidates: progress.candidates, winnerID: nil)

        case .completing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Completing Deep Review…")
                    .font(.headline)
            }
            Spacer()

        case let .checking(expectedLocations):
            ContentUnavailableView(
                "Checking Deep Review",
                systemImage: "hourglass",
                description: Text(checkingMessage(expectedLocations)),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .unavailable(reason):
            ContentUnavailableView(
                "Deep Review Unavailable",
                systemImage: "sparkle.magnifyingglass",
                description: Text(reason),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .cancelled:
            ContentUnavailableView(
                "Deep Review Cancelled",
                systemImage: "xmark.circle",
                description: Text("Run Deep Review again when you are ready."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(_, failure):
            ContentUnavailableView(
                "Deep Review Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(failureMessage(failure)),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            ContentUnavailableView(
                "No Deep Review Yet",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Run local AI subject-detail analysis for this burst group."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func checkingMessage(_ expectedLocations: [URL]) -> String {
        expectedLocations.first.map {
            "RawCull is checking the selected segmentation model at \($0.path)."
        } ?? "RawCull is checking the selected segmentation model."
    }

    private func failureMessage(_ failure: DeepAIReviewFailure) -> String {
        switch failure {
        case let .modelUnavailable(reason):
            reason

        case .noCandidates:
            "This burst group has no candidates to review."

        case let .pipelineFailed(reason):
            "The in-process segmentation pipeline failed: \(reason)"
        }
    }
}

private struct DeepAIReviewCompletedContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let result: DeepAIReviewResult

    @State private var selectedCandidateID: UUID?

    private var selectedCandidate: DeepAIReviewCandidate? {
        selectedCandidateID.flatMap { id in
            result.candidates.first { $0.fileID == id }
        }
    }

    var body: some View {
        DeepAIReviewSummaryView(result: result)

        HSplitView {
            DeepAIReviewCandidateTable(
                candidates: result.candidates,
                winnerID: result.recommendedFileID,
                selection: $selectedCandidateID,
            )
            .frame(minWidth: 660)

            DeepAIReviewMaskPreview(
                controller: controller,
                files: files,
                candidate: selectedCandidate,
            )
            .frame(minWidth: 330, idealWidth: 420)
        }
        .task(id: result.timestamp) {
            let availableIDs = Set(result.candidates.map(\.fileID))
            if selectedCandidateID.map(availableIDs.contains) != true {
                selectedCandidateID = result.recommendedFileID
                    ?? result.candidates.first?.fileID
            }
        }
    }
}

private struct DeepAIReviewMaskPreview: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let candidate: DeepAIReviewCandidate?

    @State private var mask: CGImage?
    @State private var isLoading = false

    private var file: FileItem? {
        guard let candidate else { return nil }
        return files.first { $0.id == candidate.fileID }
    }

    private var loadIdentity: String? {
        guard let candidate, let prompt = candidate.maskPromptUsed else { return nil }
        return "\(candidate.fileID.uuidString):\(prompt.rawValue)"
    }

    var body: some View {
        Group {
            if let candidate, let file {
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        ThumbnailImageView(
                            url: file.url,
                            targetSize: 1_200,
                            style: .list,
                            contentMode: .fit,
                        )

                        if let mask {
                            Image(decorative: mask, scale: 1, orientation: .up)
                                .resizable()
                                .scaledToFit()
                                .colorMultiply(.cyan)
                                .blendMode(.screen)
                                .opacity(0.72)
                                .accessibilityHidden(true)
                        }

                        if isLoading {
                            ProgressView("Loading mask…")
                                .padding(10)
                                .background(.regularMaterial, in: .rect(cornerRadius: 8))
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black, in: .rect(cornerRadius: 8))
                    .clipShape(.rect(cornerRadius: 8))

                    HStack {
                        Label(candidate.fileName, systemImage: "photo")
                            .lineLimit(1)
                        Spacer()
                        Text(mask == nil ? "Mask unavailable" : "Cyan mask overlay")
                            .foregroundStyle(mask == nil ? Color.orange : Color.secondary)
                    }
                    .font(.caption)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Mask preview for \(candidate.fileName)")
            } else {
                ContentUnavailableView(
                    "Select a Candidate",
                    systemImage: "photo.badge.magnifyingglass",
                    description: Text("Select a completed row to inspect its stored subject mask."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: loadIdentity) {
            mask = nil
            guard let candidate, loadIdentity != nil else { return }
            isLoading = true
            let loadedMask = await controller.mask(for: candidate, in: files)
            guard !Task.isCancelled else { return }
            mask = loadedMask
            isLoading = false
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deep Review progress")
        .accessibilityValue(progressAccessibilityValue)
    }

    private var progressAccessibilityValue: String {
        var value = "\(completedCount) of \(totalCount) candidates complete"
        if let currentFileName {
            value += ". Analyzing \(currentFileName)"
        }
        return value
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recommendationLabel)
        .accessibilityValue(summaryAccessibilityValue)
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

    private var summaryAccessibilityValue: String {
        let confidence = switch result.confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
        let preset = switch result.preset {
        case .auto: "Auto target"
        case .fullSubject: "Full Subject target"
        case .headFace: "Head or Face target"
        }
        if explanation.isEmpty {
            return "\(confidence). \(preset)."
        }
        return "\(confidence). \(preset). \(explanation)"
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
    @Binding var selection: UUID?

    init(
        candidates: [DeepAIReviewCandidate],
        winnerID: UUID?,
        selection: Binding<UUID?> = .constant(nil),
    ) {
        self.candidates = candidates
        self.winnerID = winnerID
        _selection = selection
    }

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
