import SwiftUI

struct CombinedReviewInspector: View {
    let feature: CombinedReviewFeature
    let inputKey: String
    let source: ReviewSourceRecord?
    let subjects: [ReviewSubjectRecord]
    let regions: [ReviewRegionRecord]
    @State private var subjectID = ""
    @Binding var regionID: String
    @State private var image: CGImage?
    @State private var tint: CGImage?
    @State private var crop: CGImage?

    private var subject: ReviewSubjectRecord? {
        subjects.first { $0.id.rawValue == subjectID }
    }

    private var region: ReviewRegionRecord? {
        regions.first { $0.id.rawValue == regionID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Source, mask and retained crop").font(.headline)
            Picker("Subject", selection: $subjectID) {
                Text("No mask").tag("")
                ForEach(subjects, id: \.id) { Text($0.concept).tag($0.id.rawValue) }
            }
            Picker("Region", selection: $regionID) {
                Text("Overview only").tag("")
                ForEach(regions, id: \.id) { region in
                    Text(CombinedReviewPresentation.regionName(region, subjects: subjects) + " · " +
                        "\(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height))")
                        .tag(region.id.rawValue)
                }
            }
            if let image, let source {
                CombinedReviewInspectionCanvas(image: image, tint: tint, sourceSize: CGSize(width: source.width, height: source.height), region: region)
                    .aspectRatio(CGFloat(source.width) / CGFloat(source.height), contentMode: .fit)
                    .clipped()
                    .allowsHitTesting(false)
                Text("Mask tint: cyan. Rectangles: requested yellow, padded orange, clipped green, encoder-retained pink.").font(.caption)
            } else {
                Text("Retained overview unavailable.")
            }
            if let region {
                if let crop {
                    Image(decorative: crop, scale: 1).resizable().scaledToFit().frame(maxHeight: 360)
                        .clipped().allowsHitTesting(false)
                } else {
                    Text("Retained crop unavailable: compact retention, eviction or cleanup.")
                }
                Text("Retained request crop · \(Int(region.sourceRect.width)) × \(Int(region.sourceRect.height))").font(.caption)
                DisclosureGroup("Crop geometry & provenance") {
                    Text(region.purpose).font(.caption)
                    Text("Region " + region.id.rawValue).font(.caption).textSelection(.enabled)
                    Text("Encoder geometry is a declared simulation, not a saved tensor: \(Int(region.encoderSize.width)) × \(Int(region.encoderSize.height)).").font(.caption)
                }
                if let support = region.support {
                    Text("Foreground retained: crop \(support.subjectForegroundRetained.formatted(.percent)), encoder \(support.encoderForegroundRetained.formatted(.percent)); source edge contact: \(support.sourceEdgeContact ? "yes" : "no").")
                    Text(support.anatomicalSupport).font(.caption)
                } else {
                    Text("Registration support unavailable for this historical region.").font(.caption)
                }
            }
            if let subject {
                DisclosureGroup("Subject registration & provenance") {
                    Text("Subject " + subject.id.rawValue).font(.caption2).textSelection(.enabled)
                    Text("Priority: " + (subject.relevance?.role.rawValue ?? "unknown") + "; " + (subject.relevance?.uncertainty ?? "Historical priority unavailable")).font(.caption)
                    Text(subject.relevance?.provenance ?? "").font(.caption2).textSelection(.enabled)
                    if let contract = subject.maskContract {
                        Text("\(contract.width) × \(contract.height), \(contract.channel.rawValue), \(contract.origin)").font(.caption)
                    }
                    if let registration = subject.registration {
                        Text(registration.transform).font(.caption)
                        if let warning = registration.warning {
                            Text(warning).foregroundStyle(.orange)
                        }
                        if registration.touchesSourceEdge {
                            Text("Foreground touches the original source edge; visibility may be partial.").font(.caption)
                        }
                    }
                }
            }
        }
        .task(id: inputKey) {
            image = nil
            let loaded = await feature.exactInput(inputKey)
            guard !Task.isCancelled else { return }
            image = loaded
            if !regions.contains(where: { $0.id.rawValue == regionID }) {
                regionID = ""
            }
        }
        .task(id: subject?.maskInputReference) {
            tint = nil
            if let key = subject?.maskInputReference, let mask = await feature.exactInput(key) {
                let loaded = try? await Task { @concurrent in try ReviewInspectionOverlay.tint(mask) }.value
                guard !Task.isCancelled, subject?.maskInputReference == key else { return }
                tint = loaded
            }
        }
        .onChange(of: regionID, initial: true) { _, _ in
            subjectID = region?.subjectID?.rawValue ?? ""
        }
        .task(id: region?.inputReference) {
            crop = nil
            if let region {
                if let key = region.inputReference {
                    let loaded = await feature.exactInput(key)
                    guard !Task.isCancelled, self.region?.inputReference == key else { return }
                    crop = loaded
                }
            }
        }
    }
}

struct CombinedReviewInspectionCanvas: View {
    let image: CGImage
    let tint: CGImage?
    let sourceSize: CGSize
    let region: ReviewRegionRecord?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / sourceSize.width, geometry.size.height / sourceSize.height)
            let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                if let tint {
                    Image(decorative: tint, scale: 1).resizable().frame(width: size.width, height: size.height)
                }
                if let region {
                    outline(region.requestedRect, color: .yellow, size: size)
                    outline(region.paddedRect, color: .orange, size: size)
                    outline(region.sourceRect, color: .green, size: size)
                    outline(region.retainedSourceRect, color: .pink, size: size)
                }
            }.frame(width: size.width, height: size.height).clipped()
        }
    }

    private func outline(_ rect: CGRect, color: Color, size: CGSize) -> some View {
        let display = ReviewInspectionOverlay.displayRect(rect, sourceSize: sourceSize, displaySize: size)
        return Rectangle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: color == .orange ? [5, 3] : []))
            .frame(width: display.width, height: display.height).offset(x: display.minX, y: display.minY)
    }
}
