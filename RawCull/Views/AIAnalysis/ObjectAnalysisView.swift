import AppKit
import SwiftUI

struct ObjectAnalysisView: View {
    @Bindable var feature: RawCullObjectAnalysisFeature
    let files: [FileItem]
    @Binding var selection: UUID?

    private var pendingFiles: [FileItem] { feature.filesNeedingAnalysis(from: files) }
    private var selectedResult: ObjectPhotoAnalysisResult? {
        selection.flatMap { id in feature.results.first { $0.fileID == id } }
    }

    var body: some View {
        VStack(spacing: 12) {
            ObjectAnalysisControls(feature: feature, files: files, pendingFiles: pendingFiles)
            ObjectAnalysisAvailabilityView(availability: feature.availability)
            if let progress = feature.progress {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(progress.completedCount),
                                 total: Double(max(progress.totalCount, 1)))
                    Text("\(progress.currentFileName): \(progress.stage.label) · \(progress.completedCount)/\(progress.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            if let failure = feature.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if feature.results.isEmpty {
                ContentUnavailableView(
                    "No Object Results Yet", systemImage: "square.3.layers.3d",
                    description: Text("Install SAM 3 and Qwen, then analyze selected or tagged photographs."),
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    ObjectPhotoResultsTable(results: feature.results, selection: $selection)
                        .frame(minWidth: 350, idealWidth: 480)
                    ObjectPhotoDetailView(result: selectedResult,
                                          file: files.first { $0.id == selectedResult?.fileID },
                                          feature: feature)
                        .frame(minWidth: 350, idealWidth: 600)
                }
            }
        }
        .padding(16)
        .task(id: feature.results.map(\.id)) {
            if selection == nil { selection = feature.results.first?.id }
        }
    }
}

private struct ObjectAnalysisControls: View {
    @Bindable var feature: RawCullObjectAnalysisFeature
    let files: [FileItem]
    let pendingFiles: [FileItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Concepts", selection: $feature.discoveryMode) {
                    Text("Automatic").tag(ObjectDiscoveryMode.automatic)
                    Text("Specific Concepts").tag(ObjectDiscoveryMode.specificConcepts)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .accessibilityLabel("Object concept mode")
                .disabled(feature.isRunning)
                if feature.discoveryMode == .specificConcepts {
                    TextField("bird, person, car", text: $feature.manualConceptText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Specific object concepts, separated by commas")
                        .disabled(feature.isRunning)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                TextField("Additional photographic criteria", text: $feature.criteria)
                    .textFieldStyle(.roundedBorder)
                    .disabled(feature.isRunning)
                if feature.isRunning {
                    Button("Cancel", systemImage: "stop.circle", role: .cancel) {
                        feature.cancel()
                    }
                } else {
                    Button("Analyze \(pendingFiles.count) Images", systemImage: "sparkles") {
                        Task { await feature.analyze(pendingFiles) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!feature.canRun || pendingFiles.isEmpty)
                    Button("Retry Failed") {
                        Task { await feature.retryFailed(files) }
                    }
                    .disabled(!feature.canRun || !feature.results.contains { !$0.isSuccessful })
                    Button("Clear Results", role: .destructive) { feature.clearResults() }
                        .disabled(feature.results.isEmpty)
                }
            }
        }
    }
}

private struct ObjectAnalysisAvailabilityView: View {
    let availability: ObjectAnalysisAvailability

    var body: some View {
        HStack {
            switch availability {
            case .checking:
                ProgressView().controlSize(.small)
                Text("Checking local SAM 3 and Qwen models…")
            case .ready:
                Label("SAM 3 and Qwen ready", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .sam3Unavailable:
                Label("Install SAM 3 in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
            case .qwenUnavailable:
                Label("Install Qwen in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
            case .bothUnavailable:
                Label("Install SAM 3 and Qwen in Settings › AI › Download AI Models", systemImage: "questionmark.folder")
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .font(.caption)
    }
}

private struct ObjectPhotoResultsTable: View {
    let results: [ObjectPhotoAnalysisResult]
    @Binding var selection: UUID?

    var body: some View {
        Table(results, selection: $selection) {
            TableColumn("File") { result in Text(result.fileName).lineLimit(1) }
            TableColumn("Objects") { result in Text(result.instances.count.formatted()) }
                .width(65)
            TableColumn("Concepts") { result in
                Text(result.concepts.joined(separator: ", ")).lineLimit(1)
            }
            TableColumn("Qwen confidence") { result in
                Text(result.assessment?.confidence.formatted(.percent.precision(.fractionLength(0))) ?? "—")
            }
            .width(90)
            TableColumn("Status") { result in
                if result.needsAssessmentRetry {
                    Text("Assessment needs retry")
                } else {
                    Text(result.failure == nil ? "Complete" : "Failed")
                }
            }
        }
        .accessibilityLabel("Object analysis results")
    }
}

private struct ObjectPhotoDetailView: View {
    let result: ObjectPhotoAnalysisResult?
    let file: FileItem?
    let feature: RawCullObjectAnalysisFeature
    @State private var image: CGImage?
    @State private var outlines: [String: CGImage] = [:]
    @State private var selectedObjectID: String?

    private var selectedCrop: CGImage? {
        guard let image,
              let descriptor = result?.instances.first(where: { $0.id == selectedObjectID })
        else { return nil }
        let rect = ObjectReviewBoardRenderer.crop(
            for: descriptor.normalizedBoundingBox,
            width: image.width, height: image.height,
        )
        return image.cropping(to: rect)
    }

    var body: some View {
        Group {
            if let result {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(result.fileName).font(.headline)
                        if let image {
                            ObjectOverviewImage(image: image, instances: result.instances,
                                                outlines: outlines)
                                .frame(height: 420)
                        }
                        if let failure = result.failure {
                            Label(failure, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        if result.instances.isEmpty && result.failure == nil {
                            ContentUnavailableView("No Matching Objects",
                                                   systemImage: "square.dashed",
                                                   description: Text("Try a different concept or photograph."))
                        } else if !result.instances.isEmpty {
                            Text("Objects").font(.headline)
                            ForEach(result.instances) { object in
                                Button {
                                    selectedObjectID = object.id
                                } label: {
                                    HStack {
                                        Text("\(object.id). \(object.concept)")
                                        if !object.aliases.isEmpty {
                                            Text("(\(object.aliases.joined(separator: ", ")))")
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("SAM 3 mask: \(object.score.formatted(.percent.precision(.fractionLength(0))))")
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Object \(object.id), \(object.concept)")
                                .accessibilityValue("SAM 3 mask score \(object.score.formatted(.percent))")
                            }
                            if let selectedCrop {
                                Image(decorative: selectedCrop, scale: 1)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 240)
                                    .accessibilityLabel("Cropped view of selected object")
                            }
                            if let assessment = result.assessment {
                                Text(assessment.imageSummary).font(.body)
                                Text("Qwen assessment confidence: \(assessment.confidence.formatted(.percent))")
                                    .font(.caption)
                                if let object = assessment.objects.first(where: { $0.id == selectedObjectID }) {
                                    ObjectAssessmentDetail(object: object)
                                }
                                ForEach(assessment.relationships, id: \.self) { relationship in
                                    Text("Relationship: \(relationship)").font(.caption)
                                }
                                ForEach(assessment.strengths, id: \.self) { Text("Strength: \($0)") }
                                ForEach(assessment.problems, id: \.self) { Text("Problem: \($0)") }
                                if !assessment.preferredObjectIDs.isEmpty {
                                    Text("Preferred objects: \(assessment.preferredObjectIDs.joined(separator: ", "))")
                                }
                            } else if let response = result.freeformResponse {
                                Text("Free-form Qwen response").font(.headline)
                                Text(response)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            } else {
                ContentUnavailableView("Select a Photo", systemImage: "photo",
                                       description: Text("Choose an analyzed photograph to inspect its objects."))
            }
        }
        .task(id: result?.fileID) {
            selectedObjectID = result?.instances.first?.id
            outlines = [:]
            image = if let file {
                await RawParserKitImageLoader.shared.thumbnailCGImage(for: file.url, maxPixelSize: 2048)
            } else { nil }
            if let result, let file {
                let masks = await feature.cachedMasks(for: result, file: file)
                var rendered: [String: CGImage] = [:]
                for (id, mask) in masks {
                    guard !Task.isCancelled else { return }
                    rendered[id] = await ObjectMaskOutlineRenderer.outline(from: mask)
                }
                if !Task.isCancelled { outlines = rendered }
            }
        }
    }
}

private struct ObjectOverviewImage: View {
    let image: CGImage
    let instances: [ObjectInstanceDescriptor]
    let outlines: [String: CGImage]

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / CGFloat(image.width),
                            geometry.size.height / CGFloat(image.height))
            let drawnWidth = CGFloat(image.width) * scale
            let drawnHeight = CGFloat(image.height) * scale
            let originX = (geometry.size.width - drawnWidth) / 2
            let originY = (geometry.size.height - drawnHeight) / 2
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: drawnWidth, height: drawnHeight)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            ForEach(instances) { object in
                let box = object.normalizedBoundingBox
                if let outline = outlines[object.id] {
                    Image(decorative: outline, scale: 1)
                        .resizable()
                        .renderingMode(.template)
                        .foregroundStyle(.yellow)
                        .frame(width: drawnWidth, height: drawnHeight)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                Rectangle()
                    .stroke(.yellow, lineWidth: 2)
                    .frame(width: box.width * drawnWidth,
                           height: box.height * drawnHeight)
                    .position(x: originX + box.midX * drawnWidth,
                              y: originY + (1 - box.midY) * drawnHeight)
                    .accessibilityLabel("Object \(object.id), \(object.concept)")
                Text(object.id)
                    .font(.caption.bold())
                    .padding(3)
                    .background(.black, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(.white)
                    .position(x: originX + box.minX * drawnWidth + 12,
                              y: originY + (1 - box.maxY) * drawnHeight + 12)
            }
        }
        .accessibilityLabel("Photograph with numbered object regions")
    }
}

private struct ObjectAssessmentDetail: View {
    let object: ObjectAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Object \(object.id): \(object.concept)").font(.headline)
            Text(object.description)
            Text("Visibility: \(object.visibility.rawValue); focus: \(object.focusQuality.rawValue)")
            if let expression = object.expression { Text("Expression: \(expression)") }
            ForEach(object.obstructions, id: \.self) { Text("Obstruction: \($0)") }
            ForEach(object.strengths, id: \.self) { Text("Strength: \($0)") }
            ForEach(object.problems, id: \.self) { Text("Problem: \($0)") }
        }
    }
}

private extension ObjectAnalysisStage {
    var label: String {
        switch self {
        case .loadingImage: "Loading image"
        case .discoveringConcepts: "Discovering concepts"
        case let .segmenting(concept, index, count): "Segmenting \(concept) (\(index)/\(count))"
        case .preparingObjectBoard: "Preparing object board"
        case .analyzingObjects: "Analyzing objects"
        case .completed: "Complete"
        }
    }
}
