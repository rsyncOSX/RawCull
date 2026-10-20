import SwiftUI

struct CombinedReviewPhotoLayout: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    let canChooseRegion: Bool
    let inspect: (String?) -> Void
    let inspectFinding: (CombinedReviewFinding) -> Void
    let showEvidence: () -> Void
    @State private var showRegions = false
    @State private var chooseRegion = false

    var body: some View {
        CombinedReviewResizableColumns(leadingFraction: 0.68) {
            CombinedReviewPhotoPreview(
                feature: feature, inputKey: result.overviewInputReference, source: result.source,
                regions: result.regions, showRegions: $showRegions, chooseRegion: $chooseRegion,
                canChooseRegion: canChooseRegion, inspect: inspect,
            ).frame(maxWidth: .infinity, alignment: .topLeading)
        } trailing: {
            CombinedReviewSummary(presentation: presentation, inspectFinding: inspectFinding, showEvidence: showEvidence)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct CombinedReviewPhotoPreview: View {
    let feature: CombinedReviewFeature
    let inputKey: String?
    let source: ReviewSourceRecord?
    let regions: [ReviewRegionRecord]
    @Binding var showRegions: Bool
    @Binding var chooseRegion: Bool
    let canChooseRegion: Bool
    let inspect: (String?) -> Void
    @State private var image: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { geometry in
                if let image {
                    let aspect = CGFloat(image.width) / CGFloat(image.height)
                    let width = min(geometry.size.width, geometry.size.height * aspect)
                    let height = width / aspect
                    ZStack(alignment: .topLeading) {
                        Image(decorative: image, scale: 1).resizable().frame(width: width, height: height)
                            .accessibilityLabel("Overview supplied to the review models")
                        if showRegions, let source {
                            ForEach(regions, id: \.id) { region in
                                Rectangle().stroke(.yellow, lineWidth: 2)
                                    .frame(width: region.sourceRect.width / CGFloat(source.width) * width,
                                           height: region.sourceRect.height / CGFloat(source.height) * height)
                                    .offset(x: region.sourceRect.minX / CGFloat(source.width) * width,
                                            y: region.sourceRect.minY / CGFloat(source.height) * height)
                            }
                        }
                        if let rect = feature.userRegion, canChooseRegion {
                            Rectangle().stroke(.cyan, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                .frame(width: rect.width * width, height: rect.height * height)
                                .offset(x: rect.minX * width, y: rect.minY * height)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                        guard chooseRegion, canChooseRegion, !feature.isRunning else { return }
                        let rect = CGRect(
                            x: min(value.startLocation.x, value.location.x) / width,
                            y: min(value.startLocation.y, value.location.y) / height,
                            width: abs(value.location.x - value.startLocation.x) / width,
                            height: abs(value.location.y - value.startLocation.y) / height,
                        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
                        if rect.width > 0.01, rect.height > 0.01 {
                            feature.userRegion = rect
                        }
                    })
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Review preview unavailable",
                                           systemImage: "photo",
                                           description: Text("Exact inputs were not retained, were evicted, or have been cleared. Findings remain available."))
                }
            }
            .aspectRatio(image.map { CGFloat($0.width) / CGFloat($0.height) } ?? 1.5, contentMode: .fit)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
            if let source {
                Text("\(source.fidelity) · \(source.width) × \(source.height) · \(source.colorSpace)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Toggle("Show reviewed regions", isOn: $showRegions).toggleStyle(.checkbox)
                    Spacer()
                    Button("Enlarge review image", systemImage: "magnifyingglass") { inspect(inputKey) }.disabled(inputKey == nil)
                }
                VStack(alignment: .leading) {
                    Toggle("Show reviewed regions", isOn: $showRegions).toggleStyle(.checkbox)
                    Button("Enlarge review image", systemImage: "magnifyingglass") { inspect(inputKey) }.disabled(inputKey == nil)
                }
            }
            if canChooseRegion {
                Toggle("Choose region for next rerun", isOn: $chooseRegion).toggleStyle(.checkbox)
                    .disabled(feature.isRunning || image == nil)
                if chooseRegion {
                    Text("Drag across the preview. Choosing a location does not establish subject or eye identity.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: inputKey) {
            image = nil
            guard let inputKey else { return }
            let loaded = await feature.exactInput(inputKey)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

private struct CombinedReviewSummary: View {
    let presentation: CombinedReviewPresentation
    let inspectFinding: (CombinedReviewFinding) -> Void
    let showEvidence: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(presentation.incomplete ? "Review with limitations" : "Review complete",
                  systemImage: presentation.incomplete ? "exclamationmark.circle" : "checkmark.circle")
                .font(.title3)
            if presentation.incomplete {
                Text("Some checks or image regions could not be fully assessed. Open evidence & limitations for details.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            CombinedReviewImportantLimits(limits: presentation.importantLimits)
            if presentation.findings.isEmpty {
                Text("Insufficient validated evidence for a finding. Completed stages remain in the technical record.")
                    .foregroundStyle(.secondary)
            }
            ForEach(presentation.findings) { finding in
                CombinedReviewFindingRow(finding: finding, isSelected: false, select: { inspectFinding(finding) })
            }
            Text("Model observations. Same-model reconciliation is not independent confirmation. Measurements are uncalibrated.")
                .font(.caption).foregroundStyle(.secondary)
            CombinedReviewCoverageCount(inspected: presentation.inspectedCount, uninspected: presentation.uninspectedCount)
            Button("View evidence & limitations", action: showEvidence)
        }.padding(16).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }
}

struct CombinedReviewFindingRow: View {
    let finding: CombinedReviewFinding
    let isSelected: Bool
    let select: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.title).font(.headline)
            Text(finding.text).textSelection(.enabled)
            if !finding.uncertainty.isEmpty {
                Text(finding.uncertainty).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if finding.isObservationOnly {
                Text("Observation only; no synthesized conclusion").font(.caption).foregroundStyle(.secondary)
            }
            if !finding.contradictions.isEmpty {
                Label("Conflicting evidence", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            Button("Inspect evidence", action: select)
                .accessibilityValue(isSelected ? "Selected finding" : "")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 8))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct CombinedReviewImportantLimits: View {
    let limits: [String]
    var body: some View {
        if !limits.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(limits, id: \.self) { Text($0) }
            }.font(.callout).padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
        }
    }
}

private struct CombinedReviewCoverageCount: View {
    let inspected: Int?
    let uninspected: Int?
    var body: some View {
        if let inspected, let uninspected {
            Text("\(inspected) regions inspected · \(uninspected) uninspected").font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Coverage report not available yet").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct CombinedReviewEvidenceLayout: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    let topic: CombinedReviewEvidenceTopic
    let selectedFindingID: String?
    @Binding var selectedRegionID: String
    let inspect: (String?) -> Void
    let selectFinding: (CombinedReviewFinding) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch topic {
            case .findings:
                CombinedReviewResizableColumns(leadingFraction: 0.38) {
                    CombinedReviewFindingsList(findings: presentation.findings, selectedID: selectedFindingID,
                                               select: selectFinding).frame(maxWidth: .infinity, alignment: .topLeading)
                } trailing: {
                    CombinedReviewEvidenceInspector(feature: feature, result: result, regionID: $selectedRegionID)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                if let finding = presentation.findings.first(where: { $0.id == selectedFindingID }) {
                    CombinedReviewFindingEvidence(finding: finding, result: result, inspect: inspect)
                }

            case .coverage:
                CombinedReviewCoverageDetails(presentation: presentation, source: result.source, omissions: result.omissions)

            case .technical:
                CombinedReviewRecordCopy(result: result)
                CombinedReviewTechnicalDetails(feature: feature, result: result, inspect: inspect)
            }
            CombinedReviewCoverageCount(inspected: presentation.inspectedCount, uninspected: presentation.uninspectedCount)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CombinedReviewFindingsList: View {
    let findings: [CombinedReviewFinding]
    let selectedID: String?
    let select: (CombinedReviewFinding) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Findings").font(.headline)
            if findings.isEmpty {
                Text("No validated findings. Inspect coverage and the completed technical stages.").foregroundStyle(.secondary)
            }
            ForEach(findings) { finding in
                CombinedReviewFindingRow(finding: finding, isSelected: finding.id == selectedID, select: { select(finding) })
            }
        }
    }
}

private struct CombinedReviewEvidenceInspector: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    @Binding var regionID: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let key = result.overviewInputReference {
                CombinedReviewInspector(feature: feature, inputKey: key, source: result.source,
                                        subjects: result.subjects, regions: result.regions, regionID: $regionID)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Retained input unavailable", systemImage: "photo").font(.headline)
                    Text("Evidence references and measurements remain in the technical record.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
            }
        }.padding(16).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }
}

private struct CombinedReviewFindingEvidence: View {
    let finding: CombinedReviewFinding
    let result: CombinedReviewResult
    let inspect: (String?) -> Void
    var body: some View {
        DisclosureGroup("Supporting references & conflicts") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(finding.evidence, id: \.self) { ref in
                    CombinedReviewEvidenceReferenceRow(reference: ref, result: result, inspect: inspect)
                }
                if !finding.contradictions.isEmpty {
                    Text("Conflicting references").font(.headline)
                    ForEach(finding.contradictions, id: \.self) { ref in
                        CombinedReviewEvidenceReferenceRow(reference: ref, result: result, inspect: inspect)
                    }
                }
            }.padding(.top, 8)
        }
    }
}

private struct CombinedReviewEvidenceReferenceRow: View {
    let reference: ReviewEvidenceReference
    let result: CombinedReviewResult
    let inspect: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(reference.kind.rawValue) · \(reference.id)").font(.caption).textSelection(.enabled)
            if let observation = result.observations.first(where: { $0.id.rawValue == reference.id }) {
                Text(observation.text).textSelection(.enabled)
                Text(observation.uncertainty).font(.caption).foregroundStyle(.secondary)
                Button("Inspect exact input") { inspect(observation.provenance.inputReference) }
            } else if let region = result.regions.first(where: { $0.id.rawValue == reference.id }) {
                Button("Inspect exact crop") { inspect(region.inputReference) }
            } else if reference.kind == .image {
                Button("Enlarge review image", systemImage: "magnifyingglass") { inspect(result.overviewInputReference) }
            }
        }
    }
}

private struct CombinedReviewCoverageDetails: View {
    let presentation: CombinedReviewPresentation
    let source: ReviewSourceRecord?
    let omissions: [ReviewRegionOmission]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Coverage & limits").font(.title3)
            CombinedReviewImportantLimits(limits: presentation.importantLimits)
            Text("Full limitations").font(.headline)
            ForEach(presentation.limitations, id: \.id) { limitation in
                Text(limitation.reason).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let source {
                DisclosureGroup("Source limitations") {
                    ForEach(source.limitations, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                }
            }
            if !omissions.isEmpty {
                DisclosureGroup("Uninspected regions") {
                    ForEach(omissions, id: \.regionID) { omission in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(omission.detail)
                            Text("\(omission.reason.rawValue) · \(omission.regionID.rawValue)").font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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

/// A SwiftUI layout keeps intrinsic height inside the review's vertical scroll view.
private struct CombinedReviewResizableColumns<Leading: View, Trailing: View>: View {
    let leadingFraction: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?

    var body: some View {
        CombinedReviewColumnLayout(leadingFraction: leadingFraction, offset: offset) {
            leading()
            Rectangle().fill(.quaternary)
                .overlay { Image(systemName: "line.3.horizontal").rotationEffect(.degrees(90)).font(.caption2).foregroundStyle(.secondary) }
                .contentShape(Rectangle())
                // The divider moves with offset. Local gesture coordinates would move with it
                // and feed the resize back into translation, making the panes oscillate.
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global).onChanged { value in
                    if dragStart == nil {
                        dragStart = offset
                    }
                    offset = (dragStart ?? 0) + value.translation.width
                }.onEnded { _ in dragStart = nil })
                .accessibilityLabel("Resize review columns")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: offset += 40
                    case .decrement: offset -= 40
                    @unknown default: break
                    }
                }
                .help("Drag to resize the review columns")
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct CombinedReviewColumnLayout: Layout {
    let leadingFraction: CGFloat
    let offset: CGFloat
    private let dividerWidth: CGFloat = 12
    private let minimumPaneWidth: CGFloat = 320

    private func widths(_ width: CGFloat) -> (CGFloat, CGFloat) {
        let usable = max(0, width - dividerWidth)
        let leading = min(max(usable * leadingFraction + offset, minimumPaneWidth), usable - minimumPaneWidth)
        return (leading, usable - leading)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 1024
        if width < 760 {
            let first = subviews[0].sizeThatFits(.init(width: width, height: nil))
            let last = subviews[2].sizeThatFits(.init(width: width, height: nil))
            return CGSize(width: width, height: first.height + 20 + last.height)
        }
        let (left, right) = widths(width)
        let first = subviews[0].sizeThatFits(.init(width: left, height: nil))
        let last = subviews[2].sizeThatFits(.init(width: right, height: nil))
        return CGSize(width: width, height: max(first.height, last.height))
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        if bounds.width < 760 {
            let first = subviews[0].sizeThatFits(.init(width: bounds.width, height: nil))
            let last = subviews[2].sizeThatFits(.init(width: bounds.width, height: nil))
            subviews[0].place(at: bounds.origin, proposal: .init(width: bounds.width, height: first.height))
            subviews[1].place(at: bounds.origin, proposal: .zero)
            subviews[2].place(at: CGPoint(x: bounds.minX, y: bounds.minY + first.height + 20),
                              proposal: .init(width: bounds.width, height: last.height))
        } else {
            let (left, right) = widths(bounds.width)
            let first = subviews[0].sizeThatFits(.init(width: left, height: nil))
            let last = subviews[2].sizeThatFits(.init(width: right, height: nil))
            subviews[0].place(at: bounds.origin, proposal: .init(width: left, height: first.height))
            subviews[1].place(at: CGPoint(x: bounds.minX + left, y: bounds.minY),
                              proposal: .init(width: dividerWidth, height: bounds.height))
            subviews[2].place(at: CGPoint(x: bounds.minX + left + dividerWidth, y: bounds.minY),
                              proposal: .init(width: right, height: last.height))
        }
    }
}
