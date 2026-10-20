//
//  QwenAnalysisView.swift
//  RawCull
//
//  Created by Thomas Evensen on 19/09/2026.
//

import SwiftUI

struct QwenAnalysisView: View {
    @Bindable var feature: RawCullQwenAnalysisFeature
    let files: [FileItem]
    @Binding var selection: UUID?

    private var selectedResult: QwenPhotoAnalysisResult? {
        selection.flatMap { id in
            feature.results.first { $0.id == id }
        }
    }

    private var pendingFiles: [FileItem] {
        feature.filesNeedingAnalysis(from: files)
    }

    var body: some View {
        VStack(spacing: 12) {
            AIAnalysisControlBar {
                TextField("Additional analysis prompt or focus criteria…", text: $feature.prompt)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .labelsHidden()
                    .accessibilityLabel("Analysis prompt or focus criteria")
                    .disabled(feature.isRunning)
                    .onSubmit(run)
            } actions: {
                if feature.isRunning {
                    Button("Cancel", systemImage: "stop.circle", role: .cancel) { feature.cancel() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Analyze \(pendingFiles.count) Images", systemImage: "sparkles", action: run)
                        .buttonStyle(.borderedProminent)
                        .disabled(!feature.canRun || pendingFiles.isEmpty)
                }
            } status: {
                QwenModelAvailabilityView(status: feature.modelStatus)
            }

            if let progress = feature.progress {
                AIAnalysisProgressView(
                    completedCount: progress.completedCount,
                    totalCount: progress.totalCount,
                    message: progress.currentFileName.map { "Analyzing \($0)" } ?? "Completing analysis…",
                )
            }
            if let failureMessage = feature.failureMessage {
                AIAnalysisErrorView(message: failureMessage)
            }

            // Data Presentation Split

            if feature.results.isEmpty {
                ContentUnavailableView(
                    "Ready to Analyze",
                    systemImage: "text.bubble",
                    description: Text("Run analysis to evaluate composition, exposure, and key details across your batch."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .aiAnalysisResultsContainer()
            } else {
                HSplitView {
                    QwenResultsTable(
                        results: feature.results,
                        selection: $selection,
                    )
                    .frame(minWidth: 400, idealWidth: 550)

                    QwenAssessmentDetail(result: selectedResult)
                        .frame(minWidth: 330, idealWidth: 420)
                }
                .aiAnalysisResultsContainer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(16)
        .task(id: feature.results.map(\.id)) {
            if selection == nil {
                selection = feature.results.first?.id
            }
        }
    }

    private func run() {
        Task { await feature.analyze(pendingFiles) }
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

            TableColumn("Model score") { result in
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
                    AIAnalysisStatusBadge(title: "Complete", color: .green)
                } else if result.failure != nil {
                    AIAnalysisStatusBadge(title: "Failed", color: .orange)
                } else if result.freeformResponse != nil {
                    AIAnalysisStatusBadge(title: "Free-form", color: .blue)
                } else {
                    AIAnalysisStatusBadge(title: "Failed", color: .orange)
                }
            }
            .width(90)
        }
        .aiAnalysisTableNavigation(ids: results.map(\.id), selection: $selection)
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
        Group {
            if result?.assessment == nil, result?.freeformResponse == nil, result?.failure == nil {
                ContentUnavailableView(
                    "Select an Image",
                    systemImage: "photo",
                    description: Text("Select an analyzed image to inspect its assessment."),
                )
            } else if let failure = result?.failure,
                      result?.assessment == nil, result?.freeformResponse == nil {
                ContentUnavailableView(
                    "Analysis Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure),
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
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
                                    Text("Model confidence")
                                        .foregroundStyle(.secondary)
                                    Text(assessment.confidence.formatted(.percent.precision(.fractionLength(0))))
                                        .monospacedDigit()
                                }
                                GridRow {
                                    Text("Eyes").foregroundStyle(.secondary)
                                    Text("Unknown; anatomy unverified")
                                }
                            }
                            .font(.subheadline)

                            Text("Scores and confidence are model judgments. Analysis uses a thumbnail requested at up to 2048 pixels. Preview processing, resizing and model input resolution limit detail; RAW recovery is untested.")
                                .font(.caption).foregroundStyle(.secondary)
                            LabeledContent("Composition evidence", value: assessment.compositionEvidence ?? "Unsupported; abstained")
                            LabeledContent("Exposure evidence", value: assessment.exposureEvidence ?? "Unsupported; abstained")
                            LabeledContent("Subject visibility evidence", value: assessment.subjectVisibilityEvidence ?? "Unsupported; abstained")
                            Divider()

                            AIAnalysisFindingsSection(title: "Strengths", values: assessment.strengths, icon: "checkmark.circle", color: .green)
                            AIAnalysisFindingsSection(title: "Issues", values: assessment.problems, icon: "exclamationmark.triangle", color: .orange)
                        } else if let result, let response = result.freeformResponse {
                            Text(result.fileName)
                                .font(.headline)
                            Text(result.failure == nil ? "Free-form Assessment" : "Rejected structured assessment")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                            if let failure = result.failure {
                                Text(failure).foregroundStyle(.orange)
                            }
                            Text(response)
                                .font(.callout)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
