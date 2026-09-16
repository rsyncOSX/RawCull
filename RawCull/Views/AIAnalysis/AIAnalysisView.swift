import SwiftUI

struct AIAnalysisView: View {
    @Bindable var viewModel: RawCullViewModel
    @Bindable var qwenAnalysisFeature: RawCullQwenAnalysisFeature
    let deepAIReviewController: DeepAIReviewController

    @State private var inputSource = AIAnalysisInputSource.gridSelection
    @State private var selectedTool = AIAnalysisTool.samCLIP

    private var inputFiles: [FileItem] {
        viewModel.aiAnalysisFiles(for: inputSource)
    }

    var body: some View {
        VStack(spacing: 0) {
            AIAnalysisHeader(
                inputSource: $inputSource,
                selectedTool: $selectedTool,
                selectedCount: viewModel.aiAnalysisFiles(for: .gridSelection).count,
                taggedCount: viewModel.aiAnalysisFiles(for: .taggedImages).count,
            )

            Divider()

            VStack(spacing: 0) {
                if inputFiles.isEmpty {
                    ContentUnavailableView(
                        "No Images to Analyze",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text(emptyDescription),
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTool {
                    case .samCLIP:
                        SAMCLIPAnalysisContainer(
                            viewModel: viewModel,
                            controller: deepAIReviewController,
                            files: inputFiles,
                        )

                    case .qwen:
                        QwenAnalysisView(
                            feature: qwenAnalysisFeature,
                            files: inputFiles,
                        )
                    }

                    Divider()

                    AIAnalysisThumbnailStrip(
                        files: inputFiles,
                        selectedFileID: viewModel.selectedFileID,
                        onSelect: { file in
                            viewModel.selectedFileID = file.id
                        },
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: inputSource) { _, _ in
            qwenAnalysisFeature.cancel()
            deepAIReviewController.cancel()
        }
        .task {
            if inputFiles.isEmpty,
               !viewModel.aiAnalysisFiles(for: .taggedImages).isEmpty
            {
                inputSource = .taggedImages
            }
        }
    }

    private var emptyDescription: String {
        switch inputSource {
        case .gridSelection:
            "Select one or more images in Grid View, then return to AI Analysis."
        case .taggedImages:
            "Tag images with two or more stars before opening AI Analysis."
        }
    }
}

private struct AIAnalysisThumbnailStrip: View {
    let files: [FileItem]
    let selectedFileID: FileItem.ID?
    let onSelect: (FileItem) -> Void

    private let thumbnailSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Selected Images")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(files) { file in
                        AIAnalysisThumbnailStripItem(
                            file: file,
                            thumbnailSize: thumbnailSize,
                            isSelected: file.id == selectedFileID,
                            onSelect: {
                                onSelect(file)
                            },
                        )
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.visible)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
    }
}

private struct AIAnalysisThumbnailStripItem: View {
    let file: FileItem
    let thumbnailSize: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                ThumbnailImageView(
                    file: file,
                    targetSize: Int(thumbnailSize * 2),
                    style: .grid,
                )
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 3 : 1),
                )

                Text(file.name)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: thumbnailSize, alignment: .leading)
            }
            .frame(width: thumbnailSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(file.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private enum AIAnalysisTool: String, CaseIterable, Identifiable {
    case samCLIP
    case qwen

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .samCLIP: "SAM 3 + CLIP"
        case .qwen: "Qwen"
        }
    }
}

private struct AIAnalysisHeader: View {
    @Binding var inputSource: AIAnalysisInputSource
    @Binding var selectedTool: AIAnalysisTool
    let selectedCount: Int
    let taggedCount: Int

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("AI Analysis")
                    .font(.title2.weight(.semibold))
                Text("Analyze only the images you selected or tagged.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("Images", selection: $inputSource) {
                Text("Selected (\(selectedCount))")
                    .tag(AIAnalysisInputSource.gridSelection)
                Text("Tagged (\(taggedCount))")
                    .tag(AIAnalysisInputSource.taggedImages)
            }
            .pickerStyle(.segmented)
            .frame(width: 280)

            Picker("Analysis", selection: $selectedTool) {
                ForEach(AIAnalysisTool.allCases) { tool in
                    Text(tool.title).tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
    }
}

private struct SAMCLIPAnalysisContainer: View {
    @Bindable var viewModel: RawCullViewModel
    let controller: DeepAIReviewController
    let files: [FileItem]

    var body: some View {
        if let signature = BurstGroupSignature(
            files: files,
            catalog: viewModel.selectedSource?.url,
        ) {
            DeepAIReviewSheetView(
                controller: controller,
                groupID: signature.hashValue,
                groupSignature: signature,
                files: files,
                onApply: { result in
                    viewModel.selectAIAnalysisRecommendation(result)
                },
                onClose: {
                    viewModel.selectMainViewMode(.grid)
                },
            )
        } else {
            ContentUnavailableView(
                "Catalog Required",
                systemImage: "folder.badge.questionmark",
                description: Text("Select a catalog before running SAM 3 + CLIP analysis."),
            )
        }
    }
}

private struct QwenAnalysisView: View {
    @Bindable var feature: RawCullQwenAnalysisFeature
    let files: [FileItem]

    @State private var selectedResultID: UUID?

    private var selectedResult: QwenPhotoAnalysisResult? {
        selectedResultID.flatMap { id in
            feature.results.first { $0.id == id }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("Additional analysis criteria", text: $feature.prompt)
                    .textFieldStyle(.roundedBorder)
                    .disabled(feature.isRunning)
                    .onSubmit(run)

                if feature.isRunning {
                    Button("Cancel", systemImage: "stop.circle", role: .cancel) {
                        feature.cancel()
                    }
                } else {
                    Button("Analyze \(files.count) Images", systemImage: "bubble.left.and.text.bubble.right") {
                        run()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!feature.canRun)
                }
            }

            QwenModelAvailabilityView(status: feature.modelStatus)

            if let progress = feature.progress {
                ProgressView(
                    value: Double(progress.completedCount),
                    total: Double(max(progress.totalCount, 1)),
                ) {
                    Text(progress.currentFileName.map { "Analyzing \($0)" } ?? "Completing analysis")
                } currentValueLabel: {
                    Text("\(progress.completedCount) of \(progress.totalCount)")
                        .monospacedDigit()
                }
            }

            if let failureMessage = feature.failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if feature.results.isEmpty {
                ContentUnavailableView(
                    "No Qwen Results Yet",
                    systemImage: "text.bubble",
                    description: Text("Qwen analyzes each image independently and returns structured, sortable results."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    QwenResultsTable(
                        results: feature.results,
                        selection: $selectedResultID,
                    )
                    .frame(minWidth: 680)

                    QwenAssessmentDetail(result: selectedResult)
                        .frame(minWidth: 300, idealWidth: 380)
                }
            }
        }
        .padding(16)
        .task(id: feature.results.map(\.id)) {
            if selectedResultID.map({ id in feature.results.contains { $0.id == id } }) != true {
                selectedResultID = feature.results.first?.id
            }
        }
    }

    private func run() {
        Task { await feature.analyze(files) }
    }
}

private struct QwenModelAvailabilityView: View {
    let status: QwenModelStatus

    var body: some View {
        switch status {
        case .notConfigured:
            Label("Choose a local Qwen vision model in Settings › AI.", systemImage: "gearshape")
                .foregroundStyle(.secondary)
        case .checking:
            ProgressView("Validating the local Qwen model…")
                .controlSize(.small)
        case let .available(_, modelName):
            Label("Local model: \(modelName)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .missing(url):
            Label("Qwen model not found at \(url.path)", systemImage: "questionmark.folder")
                .foregroundStyle(.orange)
        case let .invalid(_, reason):
            Label(reason, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}

private struct QwenResultsTable: View {
    let results: [QwenPhotoAnalysisResult]
    @Binding var selection: UUID?

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in
                Text(result.fileName).lineLimit(1)
            }
            TableColumn("Overall") { result in
                Text(score(result.assessment?.overallScore)).monospacedDigit()
            }
            TableColumn("Composition") { result in
                Text(rating(result.assessment?.compositionScore))
            }
            TableColumn("Exposure") { result in
                Text(rating(result.assessment?.exposureScore))
            }
            TableColumn("Visibility") { result in
                Text(rating(result.assessment?.subjectVisibilityScore))
            }
            TableColumn("Status") { result in
                Text(result.failure == nil ? "Complete" : "Failed")
                    .foregroundStyle(result.failure == nil ? Color.green : Color.orange)
            }
        }
    }

    private func score(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }

    private func rating(_ value: Int?) -> String {
        value.map { "\($0)/5" } ?? "—"
    }
}

private struct QwenAssessmentDetail: View {
    let result: QwenPhotoAnalysisResult?

    var body: some View {
        ScrollView {
            if let result, let assessment = result.assessment {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.fileName).font(.headline)
                    LabeledContent("Subject", value: assessment.subject)
                    LabeledContent(
                        "Confidence",
                        value: assessment.confidence.formatted(.percent.precision(.fractionLength(0))),
                    )
                    if let eyesOpen = assessment.eyesOpen {
                        LabeledContent("Eyes", value: eyesOpen ? "Open" : "Closed")
                    }
                    Divider()
                    QwenAssessmentList(title: "Strengths", values: assessment.strengths)
                    QwenAssessmentList(title: "Problems", values: assessment.problems)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if let failure = result?.failure {
                ContentUnavailableView(
                    "Analysis Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure),
                )
            } else {
                ContentUnavailableView("Select a Photo", systemImage: "photo")
            }
        }
    }
}

private struct QwenAssessmentList: View {
    let title: LocalizedStringKey
    let values: [String]

    var body: some View {
        Text(title).font(.headline)
        if values.isEmpty {
            Text("None reported").foregroundStyle(.secondary)
        } else {
            ForEach(values, id: \.self) { value in
                Text("• \(value)")
            }
        }
    }
}
