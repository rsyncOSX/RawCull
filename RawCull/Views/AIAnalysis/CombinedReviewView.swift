import SwiftUI

enum CombinedReviewEvidenceTopic: String, CaseIterable {
    case findings, coverage, technical
    var title: LocalizedStringResource {
        switch self {
        case .findings: "Findings"
        case .coverage: "Coverage & limits"
        case .technical: "Technical record"
        }
    }
}

struct CombinedReviewView: View {
    @Bindable var feature: CombinedReviewFeature
    let selection: SelectionModel
    let files: [FileItem]
    @Environment(CatalogWorkspace.self) private var catalog
    @Environment(RatingsModel.self) private var ratings
    @Environment(CullingController.self) private var culling
    @Environment(BurstWorkflowController.self) private var burstWorkflow
    /// Evidence is for checking a finding, so it stays collapsed until asked for.
    @State private var evidenceExpanded = false
    @State private var topic: CombinedReviewEvidenceTopic = .findings
    @State private var selectedFindingID: String?
    @State private var selectedRegionID = ""
    @State private var inspectedInput: CGImage?
    @State private var showInput = false
    @State private var settingsExpanded = false

    private var selectedResult: CombinedReviewResult? {
        CombinedReviewPresentation.selectedResult(in: feature.displayedResults, fileID: selection.selectedFileID)
    }

    private var decisions: ReviewDecisionActions {
        .init(catalog: catalog, ratings: ratings, culling: culling, burstWorkflow: burstWorkflow)
    }

    /// The grid's rating keys rate the photo whose review is shown. Text fields keep their own keys.
    private func handleRatingKey(_ press: KeyPress) -> KeyPress.Result {
        guard !ReviewKeyboardScope.controlOwnsKeys(NSApp.keyWindow?.firstResponder),
              press.modifiers.isDisjoint(with: [.command, .control, .option]),
              case let .rating(action) = ImageReviewKeyboardPolicy.action(for: press.characters),
              let review = selectedResult?.file else { return .ignored }
        return decisions.act(on: review) { file, _ in decisions.rate(file, action.value) } ? .handled : .ignored
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        CombinedReviewRunBar(feature: feature, files: files)
                        DisclosureGroup("Review settings & retained data", isExpanded: $settingsExpanded) {
                            CombinedReviewRunControls(feature: feature, files: files).padding(.top, 10)
                        }
                        if let error = feature.failureMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange).textSelection(.enabled)
                        }
                        if let selection = feature.selectionReport {
                            DisclosureGroup("Selection comparison") {
                                CombinedReviewComparison(feature: feature, report: selection, inspect: inspect)
                            }
                        }
                        if !feature.displayedResults.isEmpty {
                            CombinedReviewFilePicker(results: feature.displayedResults, files: files, selection: Bindable(selection).selectedFileID)
                        }
                        if let result = selectedResult {
                            let presentation = CombinedReviewPresentation(result: result)
                            Text(result.file.displayName).font(.title2).textSelection(.enabled)
                            CombinedReviewDecisionBar(review: result.file, decisions: decisions)
                            CombinedReviewPhotoLayout(
                                feature: feature, result: result, presentation: presentation,
                                canChooseRegion: files.count == 1 && files.first?.id == result.file.fileID,
                                inspect: inspect,
                                inspectFinding: { openEvidence($0, result: result, scroller: scroller) },
                                showEvidence: { openEvidence(.coverage, scroller: scroller) },
                            )
                            DisclosureGroup("Evidence & details", isExpanded: $evidenceExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Picker("Evidence section", selection: $topic) {
                                        ForEach(CombinedReviewEvidenceTopic.allCases, id: \.rawValue) { Text($0.title).tag($0) }
                                    }.pickerStyle(.segmented).frame(maxWidth: 560)
                                    CombinedReviewEvidenceLayout(
                                        feature: feature, result: result, presentation: presentation, topic: topic,
                                        selectedFindingID: selectedFindingID, selectedRegionID: $selectedRegionID,
                                        inspect: inspect, selectFinding: { openEvidence($0, result: result, scroller: scroller) },
                                    )
                                }.padding(.top, 10)
                            }
                            .id(Self.evidenceAnchor)
                        } else {
                            ContentUnavailableView(
                                feature.displayedResults.isEmpty ? "Ready to Analyze" : "No review for this image",
                                systemImage: "photo.badge.magnifyingglass",
                                description: Text("Select 1–8 images and start a local analyze. Saved analyzis remain available in the image picker."),
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .aiAnalysisResultsContainer()
                        }
                        if !feature.taskHistory.isEmpty {
                            DisclosureGroup("Run history & diagnostics") {
                                CombinedReviewTaskHistory(
                                    feature: feature, runs: feature.taskHistory,
                                    activeRunID: feature.isRunning ? feature.manifest?.snapshot.id : nil,
                                )
                            }
                        }
                    }
                    .frame(
                        maxWidth: .infinity,
                        minHeight: selectedResult == nil ? max(0, geometry.size.height - 40) : 0,
                        alignment: .topLeading,
                    )
                    .padding(20)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(characters: CharacterSet(charactersIn: "xXpP012345tT")) { press in
            handleRatingKey(press)
        }
        .task { await feature.restoreStoredRun() }
        .task(id: "\(files.map { "\($0.id)-\($0.url.absoluteString)-\(String(describing: $0.afFocusNormalized))" })-\(feature.isRunning)") {
            await feature.prepareParameters(files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name, normalizedAFPoint: $0.afFocusNormalized, iso: $0.exifData?.isoValue) })
        }
        .task(id: "\(feature.manifest?.snapshot.id.uuidString ?? "none")-\(feature.isRunning)") {
            await feature.prepareResumeParameters()
        }
        .onChange(of: selectedResult?.file.id) { _, _ in
            selectedFindingID = nil
            selectedRegionID = ""
        }
        .onChange(of: feature.displayedResults.map(\.file.fileID), initial: true) { _, ids in
            if selection.selectedFileID == nil {
                selection.selectedFileID = ids.first
            }
        }
        .sheet(isPresented: $showInput) {
            VStack(spacing: 12) {
                Text("Retained request image before model preprocessing").font(.headline)
                if let inspectedInput {
                    Image(decorative: inspectedInput, scale: 1).resizable().scaledToFit()
                        .frame(maxWidth: 900, maxHeight: 650).accessibilityLabel("Retained review input")
                } else {
                    Text("Input unavailable: compact retention, cache eviction, or cleanup.")
                }
                Button("Close") { showInput = false }
            }.padding(20)
        }
    }

    private static let evidenceAnchor = "evidence"

    private func openEvidence(_ finding: CombinedReviewFinding, result: CombinedReviewResult, scroller: ScrollViewProxy) {
        selectedFindingID = finding.id
        selectedRegionID = CombinedReviewPresentation.supportingRegion(for: finding, in: result)?.rawValue ?? ""
        openEvidence(.findings, scroller: scroller)
    }

    /// Opens the evidence section at a topic and scrolls it into view.
    private func openEvidence(_ topic: CombinedReviewEvidenceTopic, scroller: ScrollViewProxy) {
        self.topic = topic
        evidenceExpanded = true
        withAnimation { scroller.scrollTo(Self.evidenceAnchor, anchor: .top) }
    }

    private func inspect(_ key: String?) {
        Task {
            inspectedInput = if let key {
                await feature.exactInput(key)
            } else {
                nil
            }
            showInput = true
        }
    }
}

private struct CombinedReviewRunBar: View {
    @Bindable var feature: CombinedReviewFeature
    let files: [FileItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Preset", selection: $feature.preset) {
                ForEach(ReviewPreset.allCases, id: \.rawValue) { preset in
                    Text(preset.title).tag(preset)
                        .disabled(feature.qwenUnavailableReason != nil && preset.usedModels.contains("qwen"))
                }
            }.pickerStyle(.segmented).frame(maxWidth: 360)
                .disabled(feature.isRunning)
            Text(presetSummary).font(.caption).foregroundStyle(.secondary)
            if let status = feature.presetStatus {
                Text(status).font(.caption).foregroundStyle(.orange)
            } else if feature.preset.usedModels.contains("qwen"), let notice = feature.qwenMemoryNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            progressRow
        }
    }

    private var progressRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                Label(feature.progress, systemImage: "sparkles").font(.headline)
                if feature.isRunning {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                CombinedReviewRunActions(feature: feature, files: files)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(feature.progress).font(.headline)
                if feature.isRunning {
                    ProgressView().controlSize(.small)
                }
                CombinedReviewRunActions(feature: feature, files: files)
            }
        }
    }

    private var presetSummary: String {
        switch feature.preset {
        case .focusCheck:
            String(localized: "SAM 3 subject masks, focus measurement and CLIP. Works without the Qwen model.")

        case .describe:
            String(localized: "One Qwen pass on the whole photo. No masks, crops or measurements.")

        case .full:
            String(localized: "Qwen overview, SAM 3 masks, focus, CLIP and object crops, then a written report.")
        }
    }
}

private struct CombinedReviewRunActions: View {
    let feature: CombinedReviewFeature
    let files: [FileItem]
    var body: some View {
        HStack {
            Button("Review") {
                let selected = files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name, normalizedAFPoint: $0.afFocusNormalized, iso: $0.exifData?.isoValue) }
                Task { await feature.analyze(selected) }
            }.buttonStyle(.borderedProminent)
                .disabled(!feature.canStartReview(for: files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name, normalizedAFPoint: $0.afFocusNormalized, iso: $0.exifData?.isoValue) }))
            if feature.isRunning {
                Button("Cancel", action: feature.cancel)
            } else if feature.manifest != nil {
                Button("Resume") { Task { await feature.resume() } }
                    .disabled(feature.resumeDisabledReason != nil)
                    .help(feature.resumeDisabledReason ?? "Resume the saved review")
            }
        }
    }
}

private struct CombinedReviewFilePicker: View {
    let results: [CombinedReviewResult]
    let files: [FileItem]
    @Binding var selection: UUID?
    var body: some View {
        Picker("Image", selection: $selection) {
            Text("Choose an image").tag(nil as UUID?)
            ForEach(files) { file in Text(file.name).tag(Optional(file.id)) }
            ForEach(results, id: \.file.id) { result in
                if !files.contains(where: { $0.id == result.file.fileID }) {
                    Text("\(result.file.displayName) · Saved review").tag(Optional(result.file.fileID))
                }
            }
        }.frame(maxWidth: 460)
    }
}

private struct CombinedReviewRunControls: View {
    @Bindable var feature: CombinedReviewFeature
    let files: [FileItem]
    @State private var clearError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Review criteria", text: $feature.criteria, axis: .vertical).textFieldStyle(.roundedBorder)
                .disabled(feature.isRunning)
            ViewThatFits(in: .horizontal) {
                HStack {
                    Picker("Depth", selection: $feature.depth) {
                        ForEach(ReviewDepth.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
                    }.frame(width: 190).disabled(!feature.preset.includes(.cropObservation))
                    Picker("Source", selection: $feature.sourcePreference) {
                        Text("High-quality preview").tag(ReviewSourcePreference.highQualityPreview)
                            .disabled(feature.sourceAvailability?.previewDisabledReason != nil)
                        Text("RAW detail").tag(ReviewSourcePreference.rawDetail)
                            .disabled(feature.sourceAvailability?.rawDisabledReason != nil)
                    }.frame(width: 280)
                }
                VStack(alignment: .leading) {
                    Picker("Depth", selection: $feature.depth) {
                        ForEach(ReviewDepth.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
                    }.disabled(!feature.preset.includes(.cropObservation))
                    Picker("Source", selection: $feature.sourcePreference) {
                        Text("High-quality preview").tag(ReviewSourcePreference.highQualityPreview)
                            .disabled(feature.sourceAvailability?.previewDisabledReason != nil)
                        Text("RAW detail").tag(ReviewSourcePreference.rawDetail)
                            .disabled(feature.sourceAvailability?.rawDisabledReason != nil)
                    }
                }
            }.disabled(feature.isRunning || feature.isCheckingParameters || feature.sourceAvailability == nil)
            VStack(alignment: .leading) {
                Toggle("Retain exact inputs", isOn: $feature.retainInputs)
                Toggle("Retain bounded rejected responses", isOn: $feature.retainRejectedResponses)
                    .help("Off by default. Retains up to 4 KB per rejected response and 32 KB per run, outside accepted evidence.")
            }.disabled(feature.isRunning)
            if feature.manifest != nil, let reason = feature.resumeDisabledReason {
                Text("Resume saved run disabled: " + reason).font(.caption).foregroundStyle(.secondary)
            }
            Text(feature.parameterStatus).font(.caption).foregroundStyle(.secondary)
            if let status = feature.criteriaStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if feature.preset.includes(.cropObservation) {
                Text("Up to \(feature.depth.cropsPerImage) crops; up to \(feature.depth.cropsPerImage + 3) Qwen passes. Crop counts are upper limits; available regions depend on the image.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Button("Clear rejected responses") {
                    Task { await clear("rejected responses") { try await feature.clearRejectedResponses() } }
                }.disabled(feature.isRunning)
                Button("Clear retained inputs") {
                    Task { await clear("retained inputs") { try await feature.clearRetainedInputs() } }
                }.disabled(feature.isRunning)
                if let clearError {
                    Text(clearError).font(.caption).foregroundStyle(.red)
                }
                if feature.userRegion != nil {
                    Button("Clear chosen region") { feature.userRegion = nil }.disabled(feature.isRunning)
                }
            }
            if files.isEmpty || files.count > 8 {
                Text("Select 1–8 images. Larger selections require an explicit expanded coverage plan; split this selection into smaller runs.").font(.caption)
            }
        }
    }

    private func clear(_ what: String, _ action: () async throws -> Void) async {
        do {
            try await action()
            clearError = nil
        } catch {
            clearError = "Could not clear \(what): \(error.localizedDescription)"
        }
    }
}

private struct CombinedReviewTaskHistory: View {
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
