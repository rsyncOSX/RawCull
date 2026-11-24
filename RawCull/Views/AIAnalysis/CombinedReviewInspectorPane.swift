import SwiftUI

/// Where the review's right-hand pane is. The pane drills down Summary → Finding → Region,
/// and every page has exactly one way back.
enum CombinedReviewRoute: Equatable {
    case summary
    case finding(String)
    /// `from` is the finding the region was opened from, so Back returns there.
    case region(ReviewRegionID, from: String?)

    var back: CombinedReviewRoute {
        switch self {
        case .summary, .finding: .summary
        case let .region(_, from): from.map { .finding($0) } ?? .summary
        }
    }

    /// The finding this page belongs to, if any.
    var findingID: String? {
        switch self {
        case .summary: nil
        case let .finding(id): id
        case let .region(_, from): from
        }
    }

    /// The region to light up on the photo for this page.
    func highlightedRegion(in result: CombinedReviewResult, presentation: CombinedReviewPresentation) -> ReviewRegionID? {
        switch self {
        case .summary:
            nil

        case let .finding(id):
            presentation.findings.first { $0.id == id }.flatMap { CombinedReviewPresentation.supportingRegion(for: $0, in: result) }

        case let .region(id, _):
            id
        }
    }

    /// Steps to the next or previous finding. From the summary, any step opens the first finding.
    func stepped(_ delta: Int, findings: [CombinedReviewFinding]) -> CombinedReviewRoute? {
        guard !findings.isEmpty else { return nil }
        guard let current = findingID, let index = findings.firstIndex(where: { $0.id == current }) else {
            return .finding(findings[0].id)
        }
        let next = (index + delta + findings.count) % findings.count
        return .finding(findings[next].id)
    }
}

/// The parts of the technical record sheet.
enum CombinedReviewRecordTab: String, CaseIterable, Identifiable {
    case coverage, technical, history
    var id: String {
        rawValue
    }

    var title: LocalizedStringResource {
        switch self {
        case .coverage: "Coverage & limits"
        case .technical: "Technical record"
        case .history: "Run history"
        }
    }
}

struct CombinedReviewInspectorPane: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    @Binding var route: CombinedReviewRoute
    /// This photo is still being reviewed, so missing findings and coverage are not results yet.
    let inProgress: Bool
    @Binding var showGeometry: Bool
    let inspect: (String?) -> Void
    let openRecord: (CombinedReviewRecordTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch route {
            case .summary:
                CombinedReviewSummaryPage(presentation: presentation, inProgress: inProgress, route: $route, openRecord: openRecord)

            case let .finding(id):
                if let finding = presentation.findings.first(where: { $0.id == id }) {
                    CombinedReviewFindingPage(feature: feature, result: result, presentation: presentation,
                                              finding: finding, route: $route, inspect: inspect)
                } else {
                    missing
                }

            case let .region(id, from):
                if let region = result.regions.first(where: { $0.id == id }) {
                    CombinedReviewRegionPage(feature: feature, result: result, presentation: presentation, region: region,
                                             backTitle: from.flatMap { id in presentation.findings.first { $0.id == id } }?.title,
                                             route: $route, showGeometry: $showGeometry, inspect: inspect, openRecord: openRecord)
                } else {
                    missing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(16)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 10) {
            CombinedReviewBackButton(title: "Summary") { route = .summary }
            Text("This item is no longer part of the review.").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Summary

private struct CombinedReviewSummaryPage: View {
    let presentation: CombinedReviewPresentation
    let inProgress: Bool
    @Binding var route: CombinedReviewRoute
    let openRecord: (CombinedReviewRecordTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if inProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Review in progress").font(.title3)
                }
                Text("Findings and coverage appear here when the review finishes.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Label(presentation.incomplete ? "Review with limitations" : "Review complete",
                      systemImage: presentation.incomplete ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.title3)
                if presentation.incomplete {
                    Text("Some checks or image regions could not be fully assessed.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
        VStack(alignment: .leading, spacing: 4) {
            CombinedReviewSectionTitle("Findings")
            if presentation.findings.isEmpty, inProgress {
                Text("No findings yet.").font(.callout).foregroundStyle(.secondary)
            } else if presentation.findings.isEmpty {
                Text("Insufficient validated evidence for a finding. Completed stages remain in the technical record.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(presentation.findings) { finding in
                CombinedReviewFindingRow(finding: finding) { route = .finding(finding.id) }
            }
        }
        if !presentation.importantLimits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                CombinedReviewSectionTitle(inProgress ? "Could not assess so far" : "Could not assess")
                ForEach(presentation.importantLimits, id: \.self) { limit in
                    Label(limit, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .symbolRenderingMode(.multicolor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(.orange.opacity(0.1), in: .rect(cornerRadius: 8))
        }
        VStack(alignment: .leading, spacing: 8) {
            Text("Model observations. Same-model reconciliation is not independent confirmation. Measurements are uncalibrated.")
                .font(.caption).foregroundStyle(.secondary)
            if !inProgress {
                CombinedReviewCoverageCount(inspected: presentation.inspectedCount, uninspected: presentation.uninspectedCount)
            }
            HStack {
                Button("Coverage & limits") { openRecord(.coverage) }
                Button("Technical record") { openRecord(.technical) }
            }
            Text("Use ↑ ↓ to step through findings and Esc to go back.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }
}

/// One finding in the summary list. The whole row opens the finding.
struct CombinedReviewFindingRow: View {
    let finding: CombinedReviewFinding
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(finding.title).font(.headline)
                        if !finding.contradictions.isEmpty {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                .help("Conflicting evidence")
                                .accessibilityLabel("Conflicting evidence")
                        }
                    }
                    Text(finding.text).lineLimit(2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(.vertical, 8).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(CombinedReviewRowButtonStyle())
        .accessibilityHint("Shows the evidence for this finding")
    }
}

private struct CombinedReviewRowButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.accentColor.opacity(0.18) : hovering ? Color.primary.opacity(0.06) : .clear,
                        in: .rect(cornerRadius: 6))
            .onHover { hovering = $0 }
    }
}

// MARK: - Finding

private struct CombinedReviewFindingPage: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    let finding: CombinedReviewFinding
    @Binding var route: CombinedReviewRoute
    let inspect: (String?) -> Void

    private var region: ReviewRegionRecord? {
        CombinedReviewPresentation.supportingRegion(for: finding, in: result).flatMap { id in result.regions.first { $0.id == id } }
    }

    var body: some View {
        HStack {
            CombinedReviewBackButton(title: "Summary") { route = .summary }
            Spacer()
            if let index = presentation.findings.firstIndex(where: { $0.id == finding.id }) {
                Text("\(index + 1) of \(presentation.findings.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Button { step(-1) } label: { Image(systemName: "chevron.up") }
                .help("Previous finding (↑)").accessibilityLabel("Previous finding")
            Button { step(1) } label: { Image(systemName: "chevron.down") }
                .help("Next finding (↓)").accessibilityLabel("Next finding")
        }
        VStack(alignment: .leading, spacing: 6) {
            Text(finding.title).font(.title3)
            Text(finding.text).textSelection(.enabled)
            if !finding.uncertainty.isEmpty {
                Text(finding.uncertainty).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if finding.isObservationOnly {
                Text("Observation only; no synthesized conclusion").font(.caption).foregroundStyle(.secondary)
            }
        }
        VStack(alignment: .leading, spacing: 10) {
            CombinedReviewSectionTitle("Evidence")
            if let region {
                CombinedReviewRetainedImage(feature: feature, key: region.inputReference,
                                            unavailable: "Retained crop unavailable: compact retention, eviction or cleanup.")
                    .frame(maxHeight: 300)
                HStack {
                    Text("\(CombinedReviewPresentation.regionName(region, subjects: result.subjects)) · \(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Region details") { route = .region(region.id, from: finding.id) }
                }
            } else {
                Text("Judged from the whole photo. The highlighted image on the left is the evidence.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.background.opacity(0.4), in: .rect(cornerRadius: 8))
        if !finding.contradictions.isEmpty {
            Label("Some evidence conflicts with this finding.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        DisclosureGroup("Supporting references") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(finding.evidence, id: \.self) { reference in
                    CombinedReviewEvidenceReferenceRow(reference: reference, result: result, inspect: inspect)
                }
                if !finding.contradictions.isEmpty {
                    Text("Conflicting references").font(.headline)
                    ForEach(finding.contradictions, id: \.self) { reference in
                        CombinedReviewEvidenceReferenceRow(reference: reference, result: result, inspect: inspect)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func step(_ delta: Int) {
        if let next = route.stepped(delta, findings: presentation.findings) {
            route = next
        }
    }
}

private struct CombinedReviewEvidenceReferenceRow: View {
    let reference: ReviewEvidenceReference
    let result: CombinedReviewResult
    let inspect: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let observation = result.observations.first(where: { $0.id.rawValue == reference.id }) {
                Text(observation.text).textSelection(.enabled)
                Text(observation.uncertainty).font(.caption).foregroundStyle(.secondary)
                Button("Inspect exact input") { inspect(observation.provenance.inputReference) }
            } else if let region = result.regions.first(where: { $0.id.rawValue == reference.id }) {
                Text(CombinedReviewPresentation.regionName(region, subjects: result.subjects))
                Button("Inspect exact crop") { inspect(region.inputReference) }
            } else if reference.kind == .image {
                Text("The whole photo").foregroundStyle(.secondary)
            }
            Text("\(reference.kind.rawValue) · \(reference.id)")
                .font(.caption2.monospaced()).foregroundStyle(.tertiary).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Region

private struct CombinedReviewRegionPage: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    let region: ReviewRegionRecord
    let backTitle: LocalizedStringResource?
    @Binding var route: CombinedReviewRoute
    @Binding var showGeometry: Bool
    let inspect: (String?) -> Void
    let openRecord: (CombinedReviewRecordTab) -> Void

    private var subject: ReviewSubjectRecord? {
        result.subjects.first { $0.id == region.subjectID }
    }

    private var usedBy: [CombinedReviewFinding] {
        presentation.findings.filter { CombinedReviewPresentation.supportingRegion(for: $0, in: result) == region.id }
    }

    var body: some View {
        HStack {
            if let backTitle {
                CombinedReviewBackButton(title: backTitle) { route = route.back }
            } else {
                CombinedReviewBackButton(title: "Summary") { route = route.back }
            }
            Spacer()
            Button("Technical record") { openRecord(.technical) }.buttonStyle(.link)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("Region: \(CombinedReviewPresentation.regionName(region, subjects: result.subjects))").font(.title3)
            Text("\(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height)) source pixels")
                .font(.caption).foregroundStyle(.secondary)
        }
        CombinedReviewRetainedImage(feature: feature, key: region.inputReference,
                                    unavailable: "Retained crop unavailable: compact retention, eviction or cleanup.")
            .frame(maxHeight: 300)
        if region.inputReference != nil {
            Button("Inspect exact crop") { inspect(region.inputReference) }
        }
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 6) {
            if let subject {
                row("Subject", Text(subject.concept))
                if let relevance = subject.relevance {
                    row("Priority", Text(Self.priority(relevance.role)))
                }
            }
            if let support = region.support {
                row("Subject kept", Text("\(support.subjectForegroundRetained.formatted(.percent)) in crop, \(support.encoderForegroundRetained.formatted(.percent)) seen by the model"))
                if support.sourceEdgeContact {
                    row("Frame edge", Text("Subject touches the photo edge; it may be cut off.").foregroundStyle(.orange))
                }
            }
            if region.edgeClipped {
                row("Clipped", Text("The crop was clipped at the photo edge."))
            }
            row("Used by", Text(usedBy.isEmpty ? "No finding cites this region directly." : usedBy.map { String(localized: $0.title) }.formatted()))
        }
        .font(.callout)
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Show crop geometry on the photo", isOn: $showGeometry).toggleStyle(.checkbox)
            HStack(spacing: 14) {
                CombinedReviewSwatch(color: .yellow, title: "Requested")
                CombinedReviewSwatch(color: .orange, title: "Padded")
                CombinedReviewSwatch(color: .green, title: "Clipped")
                CombinedReviewSwatch(color: .pink, title: "Seen by model")
            }
            .font(.caption)
        }
        DisclosureGroup("Provenance") {
            CombinedReviewRegionProvenance(region: region, subject: subject).padding(.top, 8)
        }
    }

    private func row(_ title: LocalizedStringResource, _ value: Text) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            value.textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    static func priority(_ role: ReviewSubjectRelevance.Role) -> LocalizedStringResource {
        switch role {
        case .primaryCandidate: "Main subject candidate"
        case .equallyImportantCandidate: "One of several main subjects"
        case .contextual: "Context"
        case .unassigned: "Not assigned"
        }
    }
}

/// Pipeline details for a region, left-aligned so IDs stay readable.
private struct CombinedReviewRegionProvenance: View {
    let region: ReviewRegionRecord
    let subject: ReviewSubjectRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let support = region.support {
                Text(support.anatomicalSupport)
            }
            Text(region.purpose)
            labelled("Region", region.id.rawValue)
            Text("Encoder geometry is a declared simulation, not a saved tensor: \(Int(region.encoderSize.width)) × \(Int(region.encoderSize.height)).")
            if let subject {
                labelled("Subject", subject.id.rawValue)
                if let relevance = subject.relevance {
                    Text(relevance.uncertainty)
                    Text(relevance.provenance)
                }
                if let contract = subject.maskContract {
                    Text("Mask \(contract.width) × \(contract.height), \(contract.channel.rawValue), \(contract.origin)")
                }
                if let registration = subject.registration {
                    Text(registration.transform)
                    if let warning = registration.warning {
                        Label(warning, systemImage: "info.circle")
                    }
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labelled(_ title: LocalizedStringResource, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
            Text(value).font(.caption.monospaced()).foregroundStyle(.primary)
        }
    }
}

// MARK: - Shared pieces

struct CombinedReviewCoverageCount: View {
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

struct CombinedReviewSwatch: View {
    let color: Color
    let title: LocalizedStringResource
    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).stroke(color, lineWidth: 2).frame(width: 12, height: 10)
            Text(title)
        }
    }
}

private struct CombinedReviewSectionTitle: View {
    let title: LocalizedStringResource
    init(_ title: LocalizedStringResource) {
        self.title = title
    }

    var body: some View {
        Text(title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
    }
}

private struct CombinedReviewBackButton: View {
    let title: LocalizedStringResource
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label { Text(title) } icon: { Image(systemName: "chevron.left") }
        }
        .buttonStyle(.link)
        .help("Back (Esc)")
    }
}

/// A retained review input (crop or overview) loaded on demand.
struct CombinedReviewRetainedImage: View {
    let feature: CombinedReviewFeature
    let key: String?
    let unavailable: LocalizedStringResource
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .clipShape(.rect(cornerRadius: 6))
                    .accessibilityLabel("Retained review crop")
            } else if loaded || key == nil {
                Text(unavailable).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .task(id: key) {
            image = nil
            loaded = false
            guard let key else { return }
            let result = await feature.exactInput(key)
            guard !Task.isCancelled else { return }
            image = result
            loaded = true
        }
    }
}

/// Shows one retained review input at full size.
struct CombinedReviewInputRequest: Identifiable {
    let id = UUID()
    let key: String?
}

private struct CombinedReviewInputSheet: View {
    let feature: CombinedReviewFeature
    let request: CombinedReviewInputRequest
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var loaded = false

    var body: some View {
        VStack(spacing: 12) {
            Text("Retained request image before model preprocessing").font(.headline)
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
                    .frame(maxWidth: 900, maxHeight: 650).accessibilityLabel("Retained review input")
            } else if loaded || request.key == nil {
                Text("Input unavailable: compact retention, cache eviction, or cleanup.")
            } else {
                ProgressView()
            }
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(20)
        .task {
            if let key = request.key {
                image = await feature.exactInput(key)
            }
            loaded = true
        }
    }
}

extension View {
    func combinedReviewInputSheet(_ request: Binding<CombinedReviewInputRequest?>, feature: CombinedReviewFeature) -> some View {
        sheet(item: request) { CombinedReviewInputSheet(feature: feature, request: $0) }
    }
}
