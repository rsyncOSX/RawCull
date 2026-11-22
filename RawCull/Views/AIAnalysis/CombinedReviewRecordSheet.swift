import SwiftUI

/// Everything needed to troubleshoot a review, kept out of the review flow:
/// full limitations and coverage, the structured technical record, and the run's task history.
struct CombinedReviewRecordSheet: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    @State var tab: CombinedReviewRecordTab
    @State private var inputRequest: CombinedReviewInputRequest?
    @Environment(\.dismiss) private var dismiss

    private var tabs: [CombinedReviewRecordTab] {
        feature.taskHistory.isEmpty ? [.coverage, .technical] : CombinedReviewRecordTab.allCases
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text(result.file.displayName).font(.headline)
                Picker("Section", selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .coverage:
                        CombinedReviewCoverageDetails(presentation: CombinedReviewPresentation(result: result),
                                                      source: result.source, omissions: result.omissions)
                    case .technical:
                        Text("For troubleshooting a review. Nothing here is needed to rate the photo.")
                            .font(.callout).foregroundStyle(.secondary)
                        CombinedReviewRecordCopy(result: result)
                        CombinedReviewTechnicalDetails(feature: feature, result: result, inspect: inspect)
                    case .history:
                        CombinedReviewTaskHistory(feature: feature, runs: feature.taskHistory,
                                                  activeRunID: feature.isRunning ? feature.manifest?.snapshot.id : nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .frame(minWidth: 680, idealWidth: 860, minHeight: 480, idealHeight: 680)
        .combinedReviewInputSheet($inputRequest, feature: feature)
    }

    private func inspect(_ key: String?) {
        inputRequest = .init(key: key)
    }
}

private struct CombinedReviewCoverageDetails: View {
    let presentation: CombinedReviewPresentation
    let source: ReviewSourceRecord?
    let omissions: [ReviewRegionOmission]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !presentation.importantLimits.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(presentation.importantLimits, id: \.self) { Text($0) }
                }
                .font(.callout).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
            }
            CombinedReviewCoverageCount(inspected: presentation.inspectedCount, uninspected: presentation.uninspectedCount)
            Text("Full limitations").font(.headline)
            if presentation.limitations.isEmpty {
                Text("No limitations were recorded.").foregroundStyle(.secondary)
            }
            ForEach(presentation.limitations, id: \.id) { limitation in
                Text(limitation.reason).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let source, !source.limitations.isEmpty {
                Text("Source limitations").font(.headline)
                ForEach(source.limitations, id: \.self) { Text($0).font(.callout).textSelection(.enabled) }
            }
            if !omissions.isEmpty {
                Text("Uninspected regions").font(.headline)
                ForEach(omissions, id: \.regionID) { omission in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(omission.detail)
                        Text("\(omission.reason.rawValue) · \(omission.regionID.rawValue)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CombinedReviewRecordCopy: View {
    let result: CombinedReviewResult
    @State private var message: String?
    @State private var showRecord = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Copy full technical record") {
                    do {
                        let json = try CombinedReviewTechnicalRecord(result).json()
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(json, forType: .string)
                        message = String(localized: "Copied with full precision and provenance.")
                    } catch {
                        message = String(localized: "Could not encode the technical record.")
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
            DisclosureGroup("Full structured record") {
                if showRecord, let record = try? CombinedReviewTechnicalRecord(result).json() {
                    Text(record).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button("Show full record") { showRecord = true }
                }
            }
        }
        .onChange(of: result.file.id) { _, _ in
            showRecord = false
            message = nil
        }
    }
}

struct CombinedReviewTaskHistory: View {
    let feature: CombinedReviewFeature
    let runs: [CombinedReviewRunV1]
    let activeRunID: UUID?
    @State private var expandedRuns: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task history").font(.headline)
            ForEach(runs, id: \.snapshot.id) { run in
                DisclosureGroup(isExpanded: Binding(
                    get: { expandedRuns.contains(run.snapshot.id) },
                    set: { expanded in
                        if expanded {
                            expandedRuns.insert(run.snapshot.id)
                        } else {
                            expandedRuns.remove(run.snapshot.id)
                        }
                    },
                )) {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow {
                            Text("Task").fontWeight(.semibold)
                            Text("Status").fontWeight(.semibold)
                            Text("Attempts").fontWeight(.semibold)
                            Text("Details").fontWeight(.semibold)
                        }
                        Divider().gridCellColumns(4)
                        ForEach(run.work, id: \.id) { item in
                            GridRow(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(title(item.stage))
                                    Text(item.id.rawValue.components(separatedBy: ":").dropFirst().joined(separator: ":"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                HStack(spacing: 5) {
                                    if item.state == .running, run.snapshot.id == activeRunID {
                                        ProgressView().controlSize(.mini)
                                    }
                                    Text(item.state == .running && run.snapshot.id != activeRunID ? "Interrupted" : item.state.rawValue.capitalized)
                                }
                                Text(item.attempts.formatted()).monospacedDigit()
                                VStack(alignment: .leading) {
                                    Text(item.reason ?? "—").foregroundStyle(.secondary).textSelection(.enabled)
                                    if let diagnostic = item.diagnostic {
                                        CombinedReviewDiagnosticView(feature: feature, diagnostic: diagnostic)
                                    }
                                }
                            }
                        }
                    }
                    .font(.caption)
                    .padding(.top, 8)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(run.snapshot.files.first?.displayName ?? "Review")
                        Text(run.snapshot.created.formatted(date: .abbreviated, time: .standard))
                            .font(.caption).foregroundStyle(.secondary)
                        let completed = run.work.filter { $0.state == .completed }.count
                        Text("\(completed) of \(run.work.count) tasks completed")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: .rect(cornerRadius: 8))
    }

    private func title(_ stage: ReviewStage) -> String {
        switch stage {
        case .source: "Prepare image"
        case .overview: "Overview analysis"
        case .identity: "Identify subjects"
        case .segmentation: "Subject masks"
        case .clip: "CLIP relevance"
        case .measurement: "Measure subject detail"
        case .cropObservation: "Inspect crop"
        case .reconciliation: "Reconcile evidence"
        case .report: "Generate report"
        case .comparison: "Compare images"
        }
    }
}
