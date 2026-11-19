import RawCullCore
import SwiftUI

struct AIAssessmentComparison: View {
    let entry: AIAssessmentEntry
    let viewModel: RawCullViewModel
    let access: RawCullCatalogGrant?
    let accessChecked: Bool
    let onMarkedReviewed: () -> Void

    @State private var leftID: String?
    @State private var rightID: String?
    @State private var linked = true
    @State private var leftViewport = ComparisonViewportInteractionState()
    @State private var rightViewport = ComparisonViewportInteractionState()
    @State private var activeSide = AIAssessmentSide.left
    @State private var isUpdatingReview = false
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        AIAssessmentComparisonHeader(
                            entry: entry, linked: $linked, isReviewed: verifiedGroupID.map {
                                viewModel.burstGroupReviewState(groupID: $0) == .reviewed
                            }, isUpdatingReview: isUpdatingReview, toggleReviewed: toggleReviewed,
                        )
                        HStack(alignment: .top, spacing: 12) {
                            pane(for: leftFrame, side: .left, height: max(210, geometry.size.height * 0.52))
                            if let rightFrame {
                                pane(for: rightFrame, side: .right, height: max(210, geometry.size.height * 0.52))
                            }
                        }
                    }
                    .padding(20)
                }

                Text("Click an image to activate it · P/N assessment · +/− zoom · 2–5 rate · 0 pick · X reject")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(8)
                Divider()

                AIAssessmentFilmstrip(
                    frames: entry.frames, leftID: leftFrame?.id, rightID: rightFrame?.id,
                    access: access, liveFile: liveFile, select: select, reset: resetPair, canReset: leftID != nil || rightID != nil,
                )
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .defaultFocus($hasKeyboardFocus, true)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-012345xXtT")) { press in
            guard !ReviewKeyboardScope.controlOwnsKeys(NSApp.keyWindow?.firstResponder), access != nil,
                  press.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
            if case let .rating(value) = ZoomOverlayKeyAction.resolve(
                characters: press.characters, keyCode: 0, navigationAxis: .horizontal
            ) {
                guard let frame = activeSide == .left ? leftFrame : rightFrame,
                      let file = liveFile(frame), !hasDuplicateFilename(file) else { return .ignored }
                applyRating(value, to: frame)
                return .handled
            }
            return zoomKeyboardController.handle(ImageReviewKeyboardPolicy.action(for: press.characters))
        }
        .onChange(of: linked) {
            if !linked { rightViewport = leftViewport }
        }
    }

    private var leftFrame: AIAssessmentEntry.Frame? {
        frame(leftID ?? entry.recommendation ?? entry.alternate)
    }

    private var rightFrame: AIAssessmentEntry.Frame? {
        frame(rightID ?? (entry.recommendation == nil ? nil : entry.alternate))
    }

    private func frame(_ id: String?) -> AIAssessmentEntry.Frame? {
        entry.frames.first { $0.id == id }
    }

    private func pane(for frame: AIAssessmentEntry.Frame?, side: AIAssessmentSide, height: CGFloat) -> some View {
        let viewport = side == .left || linked ? $leftViewport : $rightViewport
        let file = frame.flatMap(liveFile)
        return AIAssessmentPane(
            frame: frame, role: role(for: frame?.id), rubric: entry.request.rubric, access: access,
            accessChecked: accessChecked, isTagged: file.map { viewModel.getRating(for: $0) >= 2 },
            hasDuplicateFilename: file.map { hasDuplicateFilename($0) } ?? false,
            toggleTag: { if let frame { toggleTag(frame) } }, viewport: viewport, height: height,
            file: file, rating: file.map { ImageReviewFeaturePolicy.ratingDisplay(for: $0, using: viewModel) } ?? .unrated,
            subjectLabel: file.flatMap { viewModel.sharpnessModel.saliencyInfo[$0.id]?.subjectLabel },
            entryRecommendation: entry.recommendation, isActive: activeSide == side,
            activate: { activeSide = side; hasKeyboardFocus = true },
        )
        .frame(maxWidth: .infinity)
        .simultaneousGesture(TapGesture().onEnded {
            activeSide = side
            hasKeyboardFocus = true
        })
    }

    private var zoomKeyboardController: ImageZoomKeyboardController {
        let viewport = activeSide == .left || linked || rightFrame == nil ? $leftViewport : $rightViewport
        return ImageZoomKeyboardController(
            increaseZoom: { viewport.wrappedValue.zoomIn(resetOffsetWhenFitting: true) },
            decreaseZoom: { viewport.wrappedValue.zoomOut(resetOffsetWhenFitting: true) },
        )
    }

    private func role(for id: String?) -> LocalizedStringResource {
        if id == entry.recommendation { return "Recommendation" }
        if id == entry.alternate { return "Alternate" }
        return "Burst frame"
    }

    private func select(_ id: String, side: AIAssessmentSide) {
        activeSide = side
        hasKeyboardFocus = true
        switch side {
        case .left: leftID = id
        case .right: rightID = id
        }
    }

    private func resetPair() {
        leftID = nil
        rightID = nil
        leftViewport.resetTransform()
        rightViewport.resetTransform()
    }

    private var liveCatalog: URL? {
        guard let access, let url = viewModel.selectedSource?.url, !viewModel.scanning,
              viewModel.cullingModel.loadState == .ready, !viewModel.cullingModel.isTerminationPending,
              url.standardizedFileURL == access.url.standardizedFileURL else { return nil }
        return url
    }

    private func liveFile(_ frame: AIAssessmentEntry.Frame) -> FileItem? {
        guard let liveCatalog else { return nil }
        let expected = liveCatalog.appendingPathComponent(frame.source.relativePath).standardizedFileURL
        return viewModel.files.first {
            $0.url.standardizedFileURL == expected && $0.size == frame.source.size && $0.dateModified == frame.source.modified
        }
    }

    private var verifiedGroupID: Int? {
        guard let liveCatalog else { return nil }
        let filesByURL = Dictionary(viewModel.files.map { ($0.url.standardizedFileURL, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let ids = entry.frames.compactMap { frame -> FileItem.ID? in
            let url = liveCatalog.appendingPathComponent(frame.source.relativePath).standardizedFileURL
            guard let file = filesByURL[url], file.size == frame.source.size,
                  file.dateModified == frame.source.modified else { return nil }
            return file.id
        }
        let membership = Set(ids)
        guard membership.count == entry.frames.count else { return nil }
        let matches = viewModel.similarityModel.burstGroups.filter {
            $0.fileIDs.count == membership.count && Set($0.fileIDs) == membership
        }
        guard matches.count == 1, let group = matches.first,
              viewModel.burstGroupsInActiveCatalogScope.contains(where: {
                  $0.id == group.id && Set($0.fileIDs) == membership
              }) else { return nil }
        return group.id
    }

    private func hasDuplicateFilename(_ file: FileItem) -> Bool {
        viewModel.files.lazy.filter { $0.name == file.name }.prefix(2).count > 1
    }

    private func applyRating(_ rating: Int, to frame: AIAssessmentEntry.Frame) {
        Task {
            guard await entry.isAvailable(), let catalog = liveCatalog, let file = liveFile(frame),
                  let verified = try? frame.source.resolve(in: catalog),
                  verified == file.url.resolvingSymlinksInPath().standardizedFileURL,
                  !hasDuplicateFilename(file) else { return }
            viewModel.updateRating(for: file, rating: rating)
        }
    }

    private func toggleTag(_ frame: AIAssessmentEntry.Frame) {
        Task {
            guard await entry.isAvailable(), let catalog = liveCatalog, let file = liveFile(frame),
                  let verified = try? frame.source.resolve(in: catalog),
                  verified == file.url.resolvingSymlinksInPath().standardizedFileURL,
                  !hasDuplicateFilename(file) else { return }
            if viewModel.getRating(for: file) >= 2 {
                viewModel.cullingModel.applyRatingStates([file.name: nil], in: catalog)
                viewModel.refreshCullingDerivedState()
            } else {
                viewModel.updateRating(for: file, rating: 2)
            }
        }
    }

    private func toggleReviewed() {
        guard !isUpdatingReview else { return }
        isUpdatingReview = true
        Task {
            defer { isUpdatingReview = false }
            guard await entry.isAvailable(), let catalog = liveCatalog, let group = verifiedGroupID,
                  entry.frames.allSatisfy({ (try? $0.source.resolve(in: catalog)) != nil }) else { return }
            if viewModel.toggleBurstGroupReviewed(groupID: group) {
                onMarkedReviewed()
            }
        }
    }
}

enum AIAssessmentSide {
    case left, right
}

private struct AIAssessmentComparisonHeader: View {
    let entry: AIAssessmentEntry
    @Binding var linked: Bool
    let isReviewed: Bool?
    let isUpdatingReview: Bool
    let toggleReviewed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let number = entry.burstNumber {
                        Text("Burst \(number)").font(.title.bold())
                    } else {
                        Text("Burst assessment").font(.title.bold())
                    }
                    HStack {
                        Text("\(entry.result.assessedCount) of \(entry.frames.count) frames assessed")
                        if let confidence = entry.burstConfidence { Text(assessmentConfidence(confidence)) }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Link zoom and pan", isOn: $linked)
                    .toggleStyle(.checkbox)
                if let isReviewed {
                    Button(action: toggleReviewed) {
                        if isReviewed {
                            Label("Undo Reviewed", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Mark Reviewed", systemImage: "checkmark.circle")
                        }
                    }
                    .disabled(isUpdatingReview)
                }
            }
            if let catalog = entry.catalogName {
                Label(catalog, systemImage: "folder")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            AIAssessmentDetails(entry: entry)
            if isReviewed == nil {
                Text("Review is available when the original burst matches a burst in the open catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AIAssessmentDetails: View {
    let entry: AIAssessmentEntry

    var body: some View {
        DisclosureGroup("Assessment details") {
            VStack(alignment: .leading, spacing: 6) {
                if let catalog = entry.catalogName {
                    LabeledContent("Source catalog") { Text(verbatim: catalog) }
                }
                LabeledContent("Requested") {
                    Text(entry.requestedAt, format: .dateTime)
                }
                LabeledContent("Model") { Text(verbatim: entry.result.model) }
                LabeledContent("Criteria") {
                    Text(entry.request.rubric.map { String(localized: assessmentCriterion($0)) }.formatted(.list(type: .and)))
                }
                LabeledContent("Request ID") { Text(verbatim: entry.id.uuidString).textSelection(.enabled) }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct AIAssessmentPane: View {
    let frame: AIAssessmentEntry.Frame?
    let role: LocalizedStringResource
    let rubric: [String]
    let access: RawCullCatalogGrant?
    let accessChecked: Bool
    let isTagged: Bool?
    let hasDuplicateFilename: Bool
    let toggleTag: () -> Void
    @Binding var viewport: ComparisonViewportInteractionState
    let height: CGFloat
    let file: FileItem?
    let rating: RatingDisplay
    let subjectLabel: String?
    let entryRecommendation: String?
    let isActive: Bool
    let activate: () -> Void

    var body: some View {
        if let frame {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(verbatim: frame.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if let rank = frame.rank {
                            Text("Source rank \(rank)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let isTagged {
                        Button(action: toggleTag) {
                            Label(isTagged ? "Untag" : "Tag", systemImage: isTagged ? "tag.fill" : "tag")
                        }
                        .disabled(hasDuplicateFilename)
                        .accessibilityLabel(isTagged ? Text("Untag \(frame.name)") : Text("Tag \(frame.name)"))
                    }
                }

                if hasDuplicateFilename {
                    Text("Tagging is unavailable because more than one file in the open catalog has this filename.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                AIAssessmentPreview(
                    frame: frame, access: access, accessChecked: accessChecked, viewport: $viewport,
                    file: file, rating: rating, subjectLabel: subjectLabel, isSuggested: frame.id == entryRecommendation, activate: activate
                )
                    .id(frame.id)
                    .frame(height: height)

                HStack {
                    if let image = frame.outcome?.assessedImage {
                        if image.kind == "preview" {
                            Text("Assessed preview · \(image.width) × \(image.height)")
                        } else {
                            Text("Assessed image · \(image.kind) · \(image.width) × \(image.height)")
                        }
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                AIAssessmentFindings(outcome: frame.outcome, rubric: rubric)
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isActive ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isActive ? 2 : 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct AIAssessmentFindings: View {
    let outcome: MCPPhotoAssessmentResult.Photo?
    let rubric: [String]
    @State private var isExpanded = true

    var body: some View {
        if let findings = outcome?.findings {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rubric, id: \.self) { field in
                    LabeledContent {
                        if let score = findings[field]?.score {
                            Text("\(score)/5").monospacedDigit()
                        } else {
                            Text("Unknown")
                        }
                    } label: {
                        Text(assessmentCriterion(field))
                    }
                }
                DisclosureGroup("Findings", isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(rubric, id: \.self) { field in
                            if let evidence = findings[field]?.evidence, !evidence.isEmpty {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(assessmentCriterion(field)).font(.subheadline.bold())
                                    Text(verbatim: evidence)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        } else if let error = outcome?.errorCode {
            Label {
                Text(assessmentError(error))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
            .foregroundStyle(.secondary)
        } else {
            Text("This frame wasn’t assessed.")
                .foregroundStyle(.secondary)
        }
    }

    private func assessmentError(_ code: String) -> LocalizedStringResource {
        switch code {
        case "unreadablePhoto": "Assessment failed because the model’s preview couldn’t be read."
        case "invalidAssessment": "Assessment failed because the model returned an invalid response."
        default: "Assessment failed for this frame."
        }
    }
}

private func assessmentCriterion(_ field: String) -> LocalizedStringResource {
    switch field {
    case "composition": "Composition"
    case "exposure": "Exposure"
    case "subjectVisibility": "Subject visibility"
    default: "Custom criterion"
    }
}
