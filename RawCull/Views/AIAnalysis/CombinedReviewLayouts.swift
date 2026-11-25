import SwiftUI

/// The review's main view: the photo stays in place on the left while the inspector on the
/// right drills down from the summary to a finding and to the region behind it.
struct CombinedReviewPhotoLayout: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let presentation: CombinedReviewPresentation
    let canChooseRegion: Bool
    @Binding var route: CombinedReviewRoute
    let inspect: (String?) -> Void
    let openRecord: (CombinedReviewRecordTab) -> Void
    @State private var showRegions = true
    @State private var showMask = false
    @State private var showGeometry = false
    @State private var showFocusPoint = false
    @State private var showFocusMask = false
    @State private var chooseRegion = false
    /// Magnifier zoom in percent of the full-size preview's pixels; 0 is off. Not persisted, so Review always opens with it off.
    @State private var magnifierZoom = 0

    var body: some View {
        let highlighted = route.highlightedRegion(in: result, presentation: presentation)
        CombinedReviewResizableColumns(leadingFraction: 0.62) {
            VStack(alignment: .leading, spacing: 10) {
                CombinedReviewPhotoCanvas(
                    feature: feature, result: result, highlightedRegionID: highlighted,
                    showRegions: showRegions, showMask: showMask, showGeometry: showGeometry && highlighted != nil,
                    showFocusPoint: showFocusPoint, showFocusMask: showFocusMask,
                    magnifierZoom: chooseRegion && canChooseRegion ? 0 : magnifierZoom,
                    canChooseRegion: canChooseRegion, chooseRegion: chooseRegion && canChooseRegion,
                    selectRegion: { id in route = .region(id, from: route.findingID) },
                )
                CombinedReviewLayerBar(showRegions: $showRegions, showMask: $showMask, showGeometry: $showGeometry,
                                       showFocusPoint: $showFocusPoint, showFocusMask: $showFocusMask,
                                       hasRegions: !result.regions.isEmpty,
                                       hasMask: result.subjects.contains { $0.maskInputReference != nil },
                                       hasHighlight: highlighted != nil,
                                       hasFocusPoint: result.file.normalizedAFPoint != nil,
                                       hasOverview: result.overviewInputReference != nil)
                HStack(alignment: .firstTextBaseline) {
                    if let source = result.source {
                        Text("\(source.fidelity) · \(source.width) × \(source.height) · \(source.colorSpace)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    ReviewMagnifierPicker(zoom: $magnifierZoom).disabled(result.overviewInputReference == nil)
                }
                if canChooseRegion {
                    Toggle("Choose region for next rerun", isOn: $chooseRegion).toggleStyle(.checkbox)
                        .disabled(feature.isRunning || result.overviewInputReference == nil)
                    if chooseRegion {
                        Text("Drag across the photo. Choosing a location does not establish subject or eye identity.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        } trailing: {
            CombinedReviewInspectorPane(feature: feature, result: result, presentation: presentation, route: $route,
                                        inProgress: feature.isRunning
                                            && feature.manifest?.snapshot.files.contains { $0.id == result.file.id } == true,
                                        showGeometry: $showGeometry, inspect: inspect, openRecord: openRecord)
        }
    }
}

/// Layer toggles for the photo. They replace the old colour legend.
private struct CombinedReviewLayerBar: View {
    @Binding var showRegions: Bool
    @Binding var showMask: Bool
    @Binding var showGeometry: Bool
    @Binding var showFocusPoint: Bool
    @Binding var showFocusMask: Bool
    let hasRegions: Bool
    let hasMask: Bool
    let hasHighlight: Bool
    let hasFocusPoint: Bool
    let hasOverview: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("Show").foregroundStyle(.secondary)
            Toggle("Regions", isOn: $showRegions).disabled(!hasRegions)
            Toggle("Subject mask", isOn: $showMask).disabled(!hasMask)
            Toggle("Focus point", isOn: $showFocusPoint).disabled(!hasFocusPoint)
                .help(hasFocusPoint ? "The camera's autofocus point" : "The photo has no recorded autofocus point")
            Toggle("Focus mask", isOn: $showFocusMask).disabled(!hasOverview)
                .help("Areas measured as in focus, to compare with the focus point")
            Toggle("Crop geometry", isOn: $showGeometry).disabled(!hasHighlight)
                .help(hasHighlight ? "Requested, padded, clipped and model-retained crop rectangles"
                    : "Select a finding or region to show its crop geometry")
        }
        .toggleStyle(.checkbox)
        .font(.callout)
    }
}

/// The reviewed photo with its regions. A highlighted region is outlined in white and the rest
/// of the photo is dimmed; clicking a region opens it in the inspector.
private struct CombinedReviewPhotoCanvas: View {
    let feature: CombinedReviewFeature
    let result: CombinedReviewResult
    let highlightedRegionID: ReviewRegionID?
    let showRegions: Bool
    let showMask: Bool
    let showGeometry: Bool
    let showFocusPoint: Bool
    let showFocusMask: Bool
    let magnifierZoom: Int
    let canChooseRegion: Bool
    let chooseRegion: Bool
    let selectRegion: (ReviewRegionID) -> Void
    @Environment(SharpnessScoringModel.self) private var sharpnessModel
    @State private var image: CGImage?
    @State private var tint: CGImage?
    @State private var focusMask: NSImage?
    /// Full-resolution embedded preview for the magnifier, loaded only while it is on.
    @State private var magnifierImage: CGImage?

    /// Changes when the focus mask must be generated again; nil when it is hidden or has no image.
    private var focusMaskKey: String? {
        guard showFocusMask, image != nil, let key = result.overviewInputReference else { return nil }
        return key
    }

    private var highlighted: ReviewRegionRecord? {
        highlightedRegionID.flatMap { id in result.regions.first { $0.id == id } }
    }

    /// The mask follows the highlighted region's subject, else the first subject with a mask.
    private var maskKey: String? {
        guard showMask else { return nil }
        let subject = highlighted?.subjectID.flatMap { id in result.subjects.first { $0.id == id } }
        return subject?.maskInputReference ?? result.subjects.first { $0.maskInputReference != nil }?.maskInputReference
    }

    /// The RAW file whose full-size preview the magnifier needs; nil while the magnifier is off.
    private var magnifierKey: URL? {
        magnifierZoom > 0 ? result.file.url : nil
    }

    /// The full-resolution preview when it frames the same picture as the overview, else the overview.
    private func magnifierSource(for overview: CGImage) -> CGImage {
        guard let full = magnifierImage else { return overview }
        let fullAspect = CGFloat(full.width) / CGFloat(full.height)
        let overviewAspect = CGFloat(overview.width) / CGFloat(overview.height)
        return abs(fullAspect - overviewAspect) / overviewAspect < 0.01 ? full : overview
    }

    /// Larger regions first so smaller, nested regions sit on top and stay clickable.
    private var orderedRegions: [ReviewRegionRecord] {
        result.regions.sorted { $0.sourceRect.width * $0.sourceRect.height > $1.sourceRect.width * $1.sourceRect.height }
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let aspect = CGFloat(image.width) / CGFloat(image.height)
                let width = min(geometry.size.width, geometry.size.height * aspect)
                let size = CGSize(width: width, height: width / aspect)
                let sourceSize = result.source.map { CGSize(width: $0.width, height: $0.height) }
                    ?? CGSize(width: image.width, height: image.height)
                ZStack(alignment: .topLeading) {
                    CombinedReviewInspectionCanvas(image: image, tint: showMask ? tint : nil, sourceSize: sourceSize,
                                                   region: showGeometry ? highlighted : nil)
                        .frame(width: size.width, height: size.height)
                        .allowsHitTesting(false)
                        .accessibilityLabel("Overview supplied to the review models")
                    if showFocusMask, let focusMask {
                        ImageReviewRasterOverlay(image: Image(nsImage: focusMask), size: size, kind: .focusMap)
                    }
                    if let highlighted {
                        let rect = ReviewInspectionOverlay.displayRect(highlighted.sourceRect, sourceSize: sourceSize, displaySize: size)
                        Path { path in
                            path.addRect(CGRect(origin: .zero, size: size))
                            path.addRect(rect)
                        }
                        .fill(.black.opacity(0.45), style: FillStyle(eoFill: true))
                        .allowsHitTesting(false)
                    }
                    ForEach(orderedRegions, id: \.id) { region in
                        let isHighlighted = region.id == highlightedRegionID
                        if showRegions || isHighlighted {
                            regionBox(region, isHighlighted: isHighlighted, sourceSize: sourceSize, size: size)
                        }
                    }
                    if let rect = feature.userRegion, canChooseRegion {
                        Rectangle().stroke(.cyan, style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            .frame(width: rect.width * size.width, height: rect.height * size.height)
                            .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                            .allowsHitTesting(false)
                    }
                    if showFocusPoint, let point = result.file.normalizedAFPoint {
                        FocusPointMarker(normalizedX: point.x, normalizedY: point.y, boxSize: 28)
                            .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .shadow(color: .black.opacity(0.8), radius: 2)
                            .frame(width: size.width, height: size.height)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Autofocus point")
                    }
                }
                .frame(width: size.width, height: size.height)
                .clipped()
                .reviewMagnifier(image: magnifierSource(for: image), zoom: magnifierZoom, displaySize: size)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    guard chooseRegion, !feature.isRunning else { return }
                    let rect = CGRect(
                        x: min(value.startLocation.x, value.location.x) / size.width,
                        y: min(value.startLocation.y, value.location.y) / size.height,
                        width: abs(value.location.x - value.startLocation.x) / size.width,
                        height: abs(value.location.y - value.startLocation.y) / size.height,
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
        .overlay(alignment: .bottom) {
            CombinedReviewRunProgressCard(feature: feature, imageID: result.file.id).padding(16)
        }
        .animation(.easeInOut(duration: 0.2), value: feature.isRunning)
        .task(id: result.overviewInputReference) {
            image = nil
            guard let key = result.overviewInputReference else { return }
            let loaded = await feature.exactInput(key)
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .task(id: magnifierKey) {
            guard let url = magnifierKey else {
                magnifierImage = nil
                return
            }
            let loaded = await ZoomPreviewHandler.loadExtractedJPGPreview(for: url)
            guard !Task.isCancelled, magnifierKey == url else { return }
            magnifierImage = loaded
        }
        .task(id: maskKey) {
            tint = nil
            guard let key = maskKey, let mask = await feature.exactInput(key) else { return }
            let loaded = try? await Task { @concurrent in try ReviewInspectionOverlay.tint(mask) }.value
            guard !Task.isCancelled, maskKey == key else { return }
            tint = loaded
        }
        .task(id: focusMaskKey) {
            focusMask = nil
            guard let key = focusMaskKey, let image else { return }
            var config = sharpnessModel.effectiveFocusConfig
            let iso = result.file.iso ?? 400
            config.iso = iso
            let mask = await sharpnessModel.focusMaskModel.generateFocusMask(
                from: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)),
                scale: 1.0, configOverride: config,
                afPoint: result.file.normalizedAFPoint, iso: iso,
            )
            guard !Task.isCancelled, focusMaskKey == key else { return }
            focusMask = mask
        }
    }

    private func regionBox(_ region: ReviewRegionRecord, isHighlighted: Bool, sourceSize: CGSize, size: CGSize) -> some View {
        let rect = ReviewInspectionOverlay.displayRect(region.sourceRect, sourceSize: sourceSize, displaySize: size)
        let dimmed = highlightedRegionID != nil && !isHighlighted
        let color: Color = isHighlighted ? .white : dimmed ? .white.opacity(0.35) : .yellow
        let name = CombinedReviewPresentation.regionName(region, subjects: result.subjects)
        return Rectangle()
            .stroke(color, lineWidth: isHighlighted ? 3 : 2)
            .overlay(alignment: .topLeading) {
                Text(name)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(color, in: .rect(cornerRadius: 2))
                    .foregroundStyle(.black)
            }
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
            .onTapGesture { selectRegion(region.id) }
            .allowsHitTesting(!chooseRegion)
            .offset(x: rect.minX, y: rect.minY)
            .help("Show details for \(name)")
            .accessibilityElement()
            .accessibilityLabel("Region \(name)")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { selectRegion(region.id) }
    }
}

/// What the running review is doing, shown on the photo it is reviewing. The bar counts this
/// photo's finished tasks; the run adds crop tasks as it goes, so the total can grow.
struct CombinedReviewRunProgressCard: View {
    let feature: CombinedReviewFeature
    /// The photo to report on. Nil reports the whole run.
    let imageID: ReviewImageID?

    var body: some View {
        if feature.isRunning, let run = feature.manifest,
           imageID == nil || run.snapshot.files.contains(where: { $0.id == imageID }) {
            let own = run.work.filter { $0.imageID == imageID }
            let items = own.isEmpty ? run.work : own
            let done = items.filter(\.state.terminal).count
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(feature.progress).font(.headline).lineLimit(1)
                    Spacer(minLength: 12)
                    Text("\(done) of \(items.count) tasks").font(.callout).monospacedDigit().foregroundStyle(.secondary)
                }
                ProgressView(value: Double(done), total: Double(max(items.count, 1)))
                    .accessibilityLabel("Review progress")
                    .accessibilityValue("\(done) of \(items.count) tasks")
            }
            .padding(14)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .transition(.opacity)
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
