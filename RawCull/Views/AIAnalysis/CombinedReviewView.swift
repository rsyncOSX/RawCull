import SwiftUI

struct CombinedReviewView: View {
    @Bindable var feature: CombinedReviewFeature
    let files: [FileItem]
    @State private var inspectedInput: CGImage?
    @State private var showInput = false
    @State private var showMasks = false
    @State private var maskImages: [String: CGImage] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                controls
                Text(feature.progress).font(.headline)
                if feature.isRunning {
                    ProgressView().controlSize(.small)
                }
                if let error = feature.failureMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                if !feature.taskHistory.isEmpty {
                    CombinedReviewTaskHistory(runs: feature.taskHistory, activeRunID: feature.isRunning ? feature.manifest?.snapshot.id : nil)
                }
                if let result = feature.result {
                    evidence(result)
                } else {
                    Text("Select one image for a local review. Completed evidence stays available when you leave this view.").foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await feature.restoreStoredRun() }
        .task(id: "\(files.map { "\($0.id)-\($0.url.absoluteString)" })-\(feature.isRunning)") {
            await feature.prepareParameters(files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name) })
        }
        .task(id: "\(feature.manifest?.snapshot.id.uuidString ?? "none")-\(feature.isRunning)") {
            await feature.prepareResumeParameters()
        }
        .sheet(isPresented: $showInput) {
            VStack(spacing: 12) {
                Text("Exact unannotated model input").font(.headline)
                if let inspectedInput {
                    Image(decorative: inspectedInput, scale: 1).resizable().scaledToFit().frame(maxWidth: 900, maxHeight: 650)
                } else {
                    Text("Input unavailable: compact retention, cache eviction, or cleanup.")
                }
                Button("Close") { showInput = false }
            }.padding(20)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Review criteria", text: $feature.criteria, axis: .vertical).textFieldStyle(.roundedBorder)
                .disabled(feature.isRunning)
            HStack {
                Picker("Depth", selection: $feature.depth) {
                    ForEach(ReviewDepth.allCases, id: \.rawValue) { Text($0.rawValue.capitalized).tag($0) }
                }.frame(width: 190)
                Picker("Source", selection: $feature.sourcePreference) {
                    Text("High-quality preview").tag(ReviewSourcePreference.highQualityPreview)
                        .disabled(feature.sourceAvailability?.previewDisabledReason != nil)
                    Text("RAW detail").tag(ReviewSourcePreference.rawDetail)
                        .disabled(feature.sourceAvailability?.rawDisabledReason != nil)
                }.frame(width: 280)
                Toggle("Retain exact inputs", isOn: $feature.retainInputs)
            }.disabled(feature.isRunning || feature.isCheckingParameters || feature.sourceAvailability == nil)
            if feature.manifest != nil, let reason = feature.resumeDisabledReason {
                Text("Resume saved run disabled: " + reason).font(.caption).foregroundStyle(.secondary)
            }
            Text(feature.parameterStatus).font(.caption).foregroundStyle(.secondary)
            if let status = feature.criteriaStatus {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Text("Up to \(feature.depth.cropsPerImage) crops; up to \(feature.depth.cropsPerImage + 3) Qwen passes. Crop counts are upper limits; available regions depend on the image.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(feature.manifest == nil ? "Start review" : "Rerun with current settings") {
                    let selection = files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name) }
                    Task { await feature.analyze(selection) }
                }.disabled(!feature.canStartReview(for: files.map { ReviewSelectedFile(id: $0.id, url: $0.url, name: $0.name) }))
                Button("Cancel") { feature.cancel() }.disabled(!feature.isRunning)
                Button("Resume saved run") { Task { await feature.resume() } }.disabled(feature.isRunning || feature.manifest == nil || feature.resumeDisabledReason != nil)
                Button("Clear retained inputs") { Task { await feature.clearRetainedInputs() } }.disabled(feature.isRunning)
                if feature.userRegion != nil {
                    Button("Clear chosen region") { feature.userRegion = nil }.disabled(feature.isRunning)
                }
            }
            if files.count != 1 {
                Text("Single-image review: select exactly one image. Comparison is planned for phase 5.").font(.caption)
            }
        }
    }

    @ViewBuilder private func evidence(_ result: CombinedReviewResult) -> some View {
        Text(result.file.displayName).font(.title3)
        if let source = result.source {
            Text("\(source.fidelity) · \(source.width) × \(source.height) · \(source.colorSpace)").font(.caption).foregroundStyle(.secondary)
        }
        Button("Inspect overview input") { inspect(result.overviewInputReference) }
        if let key = result.overviewInputReference {
            CombinedReviewLocations(inputKey: key, feature: feature, regions: result.regions, source: result.source,
                                    masks: showMasks ? maskImages : [:]) { feature.userRegion = $0 }
                .frame(height: 330)
            Text("Drag across the preview to choose a region for the next rerun. A chosen location does not prove subject or eye identity.").font(.caption)
        }
        Toggle("Show available subject masks", isOn: $showMasks)
            .task(id: showMasks) {
                guard showMasks else { return }
                for subject in result.subjects {
                    if let key = subject.maskInputReference, let image = await feature.exactInput(key) {
                        maskImages[subject.id.rawValue] = image
                    }
                }
            }
        if let report = result.report {
            Text(report.incomplete ? "Review with missing evidence" : "Review").font(.headline)
            if report.claims.isEmpty {
                Text("Insufficient validated evidence for a synthesized claim. Inspect the completed stages below.")
            }
            ForEach(Array(report.claims.enumerated()), id: \.offset) { _, claim in
                VStack(alignment: .leading, spacing: 3) {
                    Text(claim.text).textSelection(.enabled)
                    Text(claim.uncertainty).font(.caption).foregroundStyle(.secondary)
                    Text("Evidence: " + claim.evidence.map(\.id).joined(separator: ", ")).font(.caption2).textSelection(.enabled)
                }
            }
        }
        ForEach(result.observations, id: \.id) { observation in
            DisclosureGroup(observation.provenance.workID.rawValue.contains(":reconcile") ? "Evidence reconciliation" : observation.regionID == nil ? "Independent overview" : "Crop observation") {
                Text(observation.text).textSelection(.enabled)
                Text(observation.uncertainty).foregroundStyle(.secondary)
                Text(observation.id.rawValue).font(.caption2).textSelection(.enabled)
                Button("Inspect exact input") { inspect(observation.provenance.inputReference) }
            }
        }
        ForEach(result.regions, id: \.id) { region in
            DisclosureGroup(region.purpose) {
                Text("Source crop \(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height)); encoder \(Int(region.encoderSize.width)) × \(Int(region.encoderSize.height)); clipped: \(region.edgeClipped ? "yes" : "no").")
                Button("Inspect exact crop") { inspect(region.inputReference) }
                if let clip = result.clip[region.id.rawValue] {
                    Text("CLIP goal relevance: \(clip.relevance.formatted(.number.precision(.fractionLength(3)))) — uncalibrated similarity.")
                }
            }
        }
        ForEach(result.measurements, id: \.id) { measurement in
            DisclosureGroup("Measured subject detail") {
                ForEach(measurement.values.keys.sorted(), id: \.self) { key in Text("\(key): \(measurement.values[key, default: 0].formatted(.number.precision(.fractionLength(3))))") }
                Text(measurement.reason ?? "").font(.caption)
                Text(measurement.id.rawValue).font(.caption2).textSelection(.enabled)
            }
        }
        DisclosureGroup("Limitations and coverage") {
            ForEach(result.limitations, id: \.id) { Text($0.reason).font(.caption).textSelection(.enabled) }
            if let report = result.report {
                Text("\(report.inspectedRegions.count) inspected regions; \(report.uninspectedRegions.count) uninspected.")
            }
        }
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

private struct CombinedReviewLocations: View {
    let inputKey: String
    let feature: CombinedReviewFeature
    let regions: [ReviewRegionRecord]
    let source: ReviewSourceRecord?
    let masks: [String: CGImage]
    let choose: (CGRect) -> Void
    @State private var image: CGImage?
    var body: some View {
        GeometryReader { geometry in
            if let image {
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                let width = min(geometry.size.width, geometry.size.height * aspect)
                let height = width / aspect
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(width: width, height: height)
                    ForEach(masks.keys.sorted(), id: \.self) { key in
                        if let mask = masks[key] {
                            Image(decorative: mask, scale: 1).resizable().frame(width: width, height: height).opacity(0.25)
                        }
                    }
                    if let source {
                        ForEach(regions, id: \.id) { region in
                            Rectangle().stroke(.yellow, lineWidth: 2)
                                .frame(width: region.sourceRect.width / CGFloat(source.width) * width, height: region.sourceRect.height / CGFloat(source.height) * height)
                                .offset(x: region.sourceRect.minX / CGFloat(source.width) * width, y: region.sourceRect.minY / CGFloat(source.height) * height)
                        }
                    }
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    guard !feature.isRunning else { return }
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x) / width,
                                      y: min(value.startLocation.y, value.location.y) / height,
                                      width: abs(value.location.x - value.startLocation.x) / width, height: abs(value.location.y - value.startLocation.y) / height)
                        .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                    if rect.width > 0.01, rect.height > 0.01 {
                        choose(rect)
                    }
                })
            } else {
                Text("Preview input unavailable under current retention.")
            }
        }.task(id: inputKey) { image = await feature.exactInput(inputKey) }
    }
}

private struct CombinedReviewTaskHistory: View {
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
                                Text(item.reason ?? "—").foregroundStyle(.secondary).textSelection(.enabled)
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
        .onChange(of: runs.first?.snapshot.id, initial: true) { _, id in
            if let id {
                expandedRuns.insert(id)
            }
        }
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
