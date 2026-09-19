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

    @State private var selectedResultID: UUID?

    private var selectedResult: QwenPhotoAnalysisResult? {
        selectedResultID.flatMap { id in
            feature.results.first { $0.id == id }
        }
    }

    private var pendingFiles: [FileItem] {
        feature.filesNeedingAnalysis(from: files)
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
                        Label("Run Analyze", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!feature.canRun || pendingFiles.isEmpty)
                }
            }

            HStack {
                QwenModelAvailabilityView(status: feature.modelStatus)
                Spacer()
            }

            if let progress = feature.progress {
                ProgressView(
                    value: Double(progress.completedCount),
                    total: Double(max(progress.totalCount, 1)),
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
                    description: Text("Run analysis to evaluate composition, exposure, and key details across your batch."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    QwenResultsTable(
                        results: feature.results,
                        selection: $selectedResultID,
                    )
                    .frame(minWidth: 400, idealWidth: 550)

                    QwenAssessmentDetail(result: selectedResult)
                        .frame(minWidth: 260, idealWidth: 320)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1),
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
                        description: Text(failure),
                    )
                } else {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "photo",
                        description: Text("Select a row in the table to inspect analysis breakdowns."),
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
