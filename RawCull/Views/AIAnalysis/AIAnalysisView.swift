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
            // Header & Control Bar
            VStack(spacing: 12) {
                AIAnalysisHeader()

                HStack(spacing: 16) {
                    Picker("Analysis Tool", selection: $selectedTool) {
                        ForEach(AIAnalysisTool.allCases) { tool in
                            Label(tool.title, systemImage: tool.systemImage)
                                .tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 320)

                    Spacer()

                    Picker("Source", selection: $inputSource) {
                        Text("Selected (\(viewModel.aiAnalysisFiles(for: .gridSelection).count))")
                            .tag(AIAnalysisInputSource.gridSelection)
                        Text("Tagged (\(viewModel.aiAnalysisFiles(for: .taggedImages).count))")
                            .tag(AIAnalysisInputSource.taggedImages)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Divider()

            // Main Content Body
            Group {
                if inputFiles.isEmpty {
                    ContentUnavailableView(
                        "No Images to Analyze",
                        systemImage: "sparkles.rectangle.stack",
                        description: Text(emptyDescription)
                    )
                } else {
                    switch selectedTool {
                    case .samCLIP:
                        SAMCLIPAnalysisContainer(
                            viewModel: viewModel,
                            controller: deepAIReviewController,
                            files: inputFiles
                        )

                    case .qwen:
                        QwenAnalysisView(
                            feature: qwenAnalysisFeature,
                            files: inputFiles
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom Thumbnail Bar (Only shown when files are present)
            if !inputFiles.isEmpty {
                Divider()
                AIAnalysisThumbnailStrip(
                    files: inputFiles,
                    inputSource: inputSource,
                    thumbnailSize: SettingsViewModel.shared.thumbnailSizeGrid
                )
            }
        }
        .onChange(of: inputSource) { _, _ in
            qwenAnalysisFeature.cancel()
            deepAIReviewController.cancel()
        }
        .task {
            if inputFiles.isEmpty && !viewModel.aiAnalysisFiles(for: .taggedImages).isEmpty {
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

// MARK: - Subviews & Controls

private enum AIAnalysisTool: String, CaseIterable, Identifiable {
    case samCLIP
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .samCLIP: "SAM 3 + CLIP"
        case .qwen: "Qwen Vision"
        }
    }

    var systemImage: String {
        switch self {
        case .samCLIP: "sparkle.magnifyingglass"
        case .qwen: "text.bubble"
        }
    }
}

private struct AIAnalysisHeader: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("AI Analysis")
                    .font(.title3.weight(.bold))
                Text("Analyze selected or tagged batch items using local vision models.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

private struct AIAnalysisThumbnailStrip: View {
    let files: [FileItem]
    let inputSource: AIAnalysisInputSource
    let thumbnailSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(inputSource == .gridSelection ? "Selected Images" : "Tagged Images")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(files.count) items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(files) { file in
                        AIAnalysisThumbnailStripItem(
                            file: file,
                            thumbnailSize: thumbnailSize
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(height: CGFloat(thumbnailSize) + 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct AIAnalysisThumbnailStripItem: View {
    let file: FileItem
    let thumbnailSize: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ThumbnailImageView(
                file: file,
                targetSize: thumbnailSize,
                style: .grid
            )
            .frame(width: CGFloat(thumbnailSize), height: CGFloat(thumbnailSize))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )

            Text(file.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(width: CGFloat(thumbnailSize))
    }
}

private struct SAMCLIPAnalysisContainer: View {
    @Bindable var viewModel: RawCullViewModel
    let controller: DeepAIReviewController
    let files: [FileItem]

    var body: some View {
        if let signature = BurstGroupSignature(
            files: files,
            catalog: viewModel.selectedSource?.url
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
                }
            )
        } else {
            ContentUnavailableView(
                "Catalog Required",
                systemImage: "folder.badge.questionmark",
                description: Text("Select a catalog before running SAM 3 + CLIP analysis.")
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
        VStack(spacing: 12) {
            // Action Control Bar
            HStack(spacing: 12) {
                TextField("Additional analysis prompt or focus criteria...", text: $feature.prompt)
                    .textFieldStyle(.roundedBorder)
                    .disabled(feature.isRunning)
                    .onSubmit(run)

                if feature.isRunning {
                    Button("Cancel", systemImage: "stop.circle", role: .cancel) {
                        feature.cancel()
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button(action: run) {
                        Label("Analyze \(files.count) Images", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!feature.canRun)
                }
            }

            HStack {
                QwenModelAvailabilityView(status: feature.modelStatus)
                Spacer()
            }

            if let progress = feature.progress {
                ProgressView(
                    value: Double(progress.completedCount),
                    total: Double(max(progress.totalCount, 1))
                ) {
                    HStack {
                        Text(progress.currentFileName.map { "Analyzing \($0)" } ?? "Completing analysis…")
                        Spacer()
                        Text("\(progress.completedCount) / \(progress.totalCount)")
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .progressViewStyle(.linear)
            }

            if let failureMessage = feature.failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Data Presentation Split
            if feature.results.isEmpty {
                ContentUnavailableView(
                    "No Qwen Results Yet",
                    systemImage: "text.bubble",
                    description: Text("Run analysis to evaluate composition, exposure, and key details across your batch.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    QwenResultsTable(
                        results: feature.results,
                        selection: $selectedResultID
                    )
                    .frame(minWidth: 400, idealWidth: 550)

                    QwenAssessmentDetail(result: selectedResult)
                        .frame(minWidth: 260, idealWidth: 320)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                )
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
        HStack(spacing: 6) {
            switch status {
            case .notConfigured:
                Label("Choose a local Qwen vision model in Settings › AI.", systemImage: "gearshape")
                    .foregroundStyle(.secondary)

            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text("Validating local model…")
                    .foregroundStyle(.secondary)

            case let .available(_, modelName):
                Label("Model ready: \(modelName)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case let .missing(url):
                Label("Model missing at \(url.lastPathComponent)", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)

            case let .invalid(_, reason):
                Label(reason, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
    }
}

private struct QwenResultsTable: View {
    let results: [QwenPhotoAnalysisResult]
    @Binding var selection: UUID?

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in
                Text(result.fileName)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 180)

            TableColumn("Overall") { result in
                Text(score(result.assessment?.overallScore))
                    .monospacedDigit()
            }
            .width(60)

            TableColumn("Composition") { result in
                Text(rating(result.assessment?.compositionScore))
            }
            .width(80)

            TableColumn("Exposure") { result in
                Text(rating(result.assessment?.exposureScore))
            }
            .width(70)

            TableColumn("Status") { result in
                if result.assessment != nil {
                    Text("Structured")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                        .foregroundStyle(.green)
                } else if result.freeformResponse != nil {
                    Text("Free-form")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                } else {
                    Text("Failed")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }
            .width(90)
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
            VStack(alignment: .leading, spacing: 14) {
                if let result, let assessment = result.assessment {
                    Text(result.fileName)
                        .font(.headline)
                        .lineLimit(1)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("Subject")
                                .foregroundStyle(.secondary)
                            Text(assessment.subject)
                                .bold()
                        }
                        GridRow {
                            Text("Confidence")
                                .foregroundStyle(.secondary)
                            Text(assessment.confidence.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        if let eyesOpen = assessment.eyesOpen {
                            GridRow {
                                Text("Eyes")
                                    .foregroundStyle(.secondary)
                                Text(eyesOpen ? "Open" : "Closed")
                            }
                        }
                    }
                    .font(.subheadline)

                    Divider()

                    QwenAssessmentList(title: "Strengths", values: assessment.strengths, icon: "checkmark.circle", color: .green)
                    QwenAssessmentList(title: "Issues", values: assessment.problems, icon: "exclamationmark.triangle", color: .orange)

                } else if let result, let response = result.freeformResponse {
                    Text(result.fileName)
                        .font(.headline)
                    Text("Free-form Assessment")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(response)
                        .font(.callout)
                        .textSelection(.enabled)

                } else if let failure = result?.failure {
                    ContentUnavailableView(
                        "Analysis Failed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(failure)
                    )
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "photo",
                        description: Text("Select a row in the table to inspect analysis breakdowns.")
                    )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct QwenAssessmentList: View {
    let title: String
    let values: [String]
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)

            if values.isEmpty {
                Text("None detected")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(values, id: \.self) { value in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                            Text(value)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
