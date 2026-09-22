import SwiftUI

struct DeepAIReviewSheetView: View {
    @Bindable var controller: DeepAIReviewController
    let groupID: Int
    let groupSignature: BurstGroupSignature
    let files: [FileItem]
    @Binding var selection: UUID?

    private var result: DeepAIReviewResult? {
        controller.result(for: groupSignature)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DeepAIReviewSheetControls(
                controller: controller,
                canRun: !files.isEmpty && !controller.isActionUnavailable,
                onRun: {
                    Task {
                        await controller.start(for: files)
                    }
                },
                onCancel: controller.cancel,
            )

            HStack {
                SAM3ModelAvailabilityView(status: controller.modelStatus)
                Spacer()
            }

            Divider()

            DeepAIReviewSheetContent(
                controller: controller,
                files: files,
                completedFiles: controller.completedFiles,
                completedCandidates: controller.completedCandidates,
                state: controller.presentationState(
                    groupID: groupID,
                    groupSignature: groupSignature,
                ),
                selection: $selection,
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

private struct SAM3ModelAvailabilityView: View {
    let status: RawCullAICapabilityStatus

    var body: some View {
        HStack(spacing: 6) {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Validating local model…")
                    .foregroundStyle(.secondary)

            case .available:
                Label("Model ready: SAM 3", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .missing:
                Label("Download SAM 3 in Settings › AI.", systemImage: "arrow.down.circle")
                    .foregroundStyle(.orange)

            case let .invalid(_, reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)

            case let .unavailable(reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }
}

private struct DeepAIReviewSheetControls: View {
    @Bindable var controller: DeepAIReviewController
    let canRun: Bool
    let onRun: () -> Void
    let onCancel: () -> Void

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

            Spacer()

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
        }
    }
}

private struct DeepAIReviewSheetContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let completedFiles: [FileItem]
    let completedCandidates: [DeepAIReviewCandidate]
    let state: DeepAIReviewPresentationState
    @Binding var selection: UUID?

    var body: some View {
        if completedCandidates.isEmpty {
            emptyContent
        } else {
            if case let .preparing(_, totalCount) = state {
                DeepAIReviewProgressHeader(
                    completedCount: 0,
                    totalCount: totalCount,
                    currentFileName: nil,
                )
            } else if case let .running(progress) = state {
                DeepAIReviewProgressHeader(
                    completedCount: progress.completedCount,
                    totalCount: progress.totalCount,
                    currentFileName: progress.currentFileName,
                )
            } else if case .completing = state {
                ProgressView("Completing Deep Review…")
            }

            DeepAIReviewHistoryContent(
                controller: controller,
                files: completedFiles,
                candidates: completedCandidates,
                selection: $selection,
            )
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch state {
        case .completed:
            ContentUnavailableView(
                "No Deep Review Yet",
                systemImage: "sparkle.magnifyingglass",
                description: Text("Select new images to analyze."),
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .preparing(_, totalCount):
            let placeholders = files.enumerated().map { index, file in
                DeepAIReviewCandidate.placeholder(rank: index + 1, file: file)
            }
            DeepAIReviewProgressHeader(
                completedCount: 0,
                totalCount: totalCount,
                currentFileName: nil,
            )
            DeepAIReviewCandidateTable(
                candidates: placeholders,
                winnerID: nil,
                selection: $selection,
            )

        case let .running(progress):
            DeepAIReviewProgressHeader(
                completedCount: progress.completedCount,
                totalCount: progress.totalCount,
                currentFileName: progress.currentFileName,
            )
            DeepAIReviewCandidateTable(
                candidates: progress.candidates,
                winnerID: nil,
                selection: $selection,
            )

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

private struct DeepAIReviewHistoryContent: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let candidates: [DeepAIReviewCandidate]
    @Binding var selection: UUID?

    private var selectedCandidate: DeepAIReviewCandidate? {
        selection.flatMap { id in
            candidates.first { $0.fileID == id }
        }
    }

    var body: some View {
        HSplitView {
            DeepAIReviewCandidateTable(
                candidates: candidates,
                winnerID: nil,
                selection: $selection,
            )
            .frame(minWidth: 660)

            DeepAIReviewMaskPreview(
                controller: controller,
                files: files,
                candidate: selectedCandidate,
            )
            .frame(minWidth: 330, idealWidth: 420)
        }
        .task(id: candidates.map(\.fileID)) {
            let availableIDs = Set(candidates.map(\.fileID))
            if selection.map(availableIDs.contains) != true {
                selection = candidates.first?.fileID
            }
        }
    }
}

private struct DeepAIReviewMaskPreview: View {
    let controller: DeepAIReviewController
    let files: [FileItem]
    let candidate: DeepAIReviewCandidate?

    @State private var maskOverlay: CGImage?
    @State private var isLoading = false
    @State private var isOrganicOutline = false

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
                            targetSize: 1200,
                            style: .list,
                            contentMode: .fit,
                        )

                        if let maskOverlay {
                            Image(decorative: maskOverlay, scale: 1, orientation: .up)
                                .resizable()
                                .scaledToFit()
                                .colorMultiply(.orange)
                                .blendMode(.screen)
                                .opacity(0.95)
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
                        Text(maskOverlayLabel)
                            .foregroundStyle(maskOverlay == nil ? Color.orange : Color.secondary)
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
            maskOverlay = nil
            isOrganicOutline = false
            isLoading = false
            guard let candidate, loadIdentity != nil else { return }
            isLoading = true
            let loadedMask = await controller.mask(for: candidate, in: files)
            guard !Task.isCancelled else {
                isLoading = false
                return
            }

            if let loadedMask {
                let outline = await DeepAIReviewMaskOutlineRenderer.outline(from: loadedMask)
                guard !Task.isCancelled else {
                    isLoading = false
                    return
                }
                if let outline {
                    maskOverlay = outline
                    isOrganicOutline = true
                } else {
                    // The stored subject mask remains a useful fallback if Core
                    // Image cannot derive a contour on a particular machine.
                    maskOverlay = loadedMask
                }
            } else {
                maskOverlay = nil
            }
            isLoading = false
        }
    }

    private var maskOverlayLabel: LocalizedStringResource {
        if isOrganicOutline {
            "Orange subject outline"
        } else if maskOverlay != nil {
            "Orange subject mask"
        } else {
            "Mask unavailable"
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

private struct DeepAIReviewCandidateTable: View {
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

extension DeepAIReviewCandidate {
    /// A "not yet analyzed" row for a file, used to populate the candidate
    /// table immediately when Deep Review is preparing to run, before any
    /// real scores exist.
    static func placeholder(rank: Int, file: FileItem) -> DeepAIReviewCandidate {
        DeepAIReviewCandidate(
            fileID: file.id,
            fileName: file.url.lastPathComponent,
            rank: rank,
            isCompleted: false,
            deepScore: nil,
            normalSharpnessScore: nil,
            broadSubjectScore: nil,
            localDetailScore: nil,
            fineDetailScore: nil,
            maskPromptUsed: nil,
            maskConfidence: nil,
            maskCoverage: nil,
            autofocusInsideMask: nil,
            promptVerified: nil,
            usedFallbackMask: false,
            issues: [],
        )
    }
}
