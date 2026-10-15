import CoreAICLIPBackend
import CoreAISAM3Backend
import CoreGraphics
import CoreImage
import Foundation
import PhotoAIWorkflows
@testable import RawCull
import Testing

/// Opt-in admission/structured-response probe. Uses an already installed verified
/// Qwen bundle and an explicitly supplied local image; never downloads assets.
@Suite("Combined Review installed-model probe")
struct CombinedReviewRealModelTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_COMBINED_REVIEW_RUN"] == "1"))
    @MainActor func `installed Qwen produces a bounded inspectable review`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let modelPath = try #require(environment["RAWCULL_COMBINED_REVIEW_QWEN"])
        let imagePath = try #require(environment["RAWCULL_COMBINED_REVIEW_IMAGE"])
        let modelURL = URL(fileURLWithPath: modelPath), imageURL = URL(fileURLWithPath: imagePath)
        let runtime = QwenInferenceRuntime()
        let status = await runtime.validate(url: modelURL)
        try #require(status.isAvailable)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CombinedReviewProbe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let samURL = environment["RAWCULL_COMBINED_REVIEW_SAM3"].map { URL(fileURLWithPath: $0) }
        let segmentation = try samURL.map { try ObjectSegmentationService(provider: CoreAISAM3Provider(modelBundleURL: $0), stores: [], maxSide: 4320, maximumInstanceCount: 8) }
        let clipURL = environment["RAWCULL_COMBINED_REVIEW_CLIP"].map { URL(fileURLWithPath: $0) }
        let clipProvider = try clipURL.map { try CoreAICLIPProvider(modelBundleURL: $0) }
        let backend = ReviewRecordingBackend(live: CombinedReviewLiveBackend(qwen: runtime, qwenURL: modelURL, segmentation: segmentation,
                                                                             samIdentity: samURL?.path, clipProvider: clipProvider, clipURL: clipURL))
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: root), lease: CombinedReviewLease(), backendFactory: { backend })
        await feature.analyze([.init(id: UUID(), url: imageURL, name: imageURL.lastPathComponent)])
        let result = try #require(feature.result)
        let run = try #require(feature.manifest)
        let diagnostic = await ProbeDiagnostic(run: run, source: result.source, regions: result.regions, report: result.report,
                                               observations: result.observations, failures: result.failures, responses: backend.responses)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(diagnostic)
        Attachment.record(String(decoding: bytes, as: UTF8.self), named: "combined-review-probe.json")
        if let output = environment["RAWCULL_COMBINED_REVIEW_OUTPUT"] {
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: output).lastPathComponent)
            try bytes.write(to: outputURL, options: .atomic)
            print("Combined Review probe diagnostic: " + outputURL.path)
        }
        #expect(result.report != nil)
        #expect(result.observations.contains { $0.regionID != nil && $0.availability == .available })
        #expect(result.report?.claims.isEmpty == false)
        #expect(run.budget.attempts[.overview] == 1)
        #expect(run.budget.attempts[.crop, default: 0] <= run.snapshot.depth.cropsPerImage)
        #expect(run.budget.attempts[.report] == 1)
        let input = try #require(result.overviewInputReference)
        #expect(await feature.exactInput(input) != nil)
        // A rejected real response must remain a stage failure, never a finding.
        for observation in result.observations {
            #expect(observation.availability != .unavailable)
        }
        await runtime.clear()
    }

    /// Full local regression; artifacts survive failure for inspection. Never uses the app's store.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_COMBINED_SIX_RUN"] == "1"))
    @MainActor func `selected ARWs complete full model review with criterion coverage`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_SELECTION_DIRECTORY"]))
        let root = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_SIX_OUTPUT"]))
        try #require(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let selectedNames = try #require(environment["RAWCULL_COMBINED_SIX_NAMES"])
        let names = try JSONDecoder().decode([String].self, from: Data(selectedNames.utf8))
        try #require(!names.isEmpty && Set(names).count == names.count)
        try #require(names.allSatisfy { URL(fileURLWithPath: $0).lastPathComponent == $0 && $0.lowercased().hasSuffix(".arw") })
        let frozen = environment["RAWCULL_COMBINED_SIX_FROZEN"] == "1"
        var batches: [String] = []
        for start in stride(from: 0, to: names.count, by: 8) {
            let batchNames = Array(names[start ..< min(start + 8, names.count)])
            let batchName = "batch-\(start / 8 + 1)"
            let batchRoot = names.count <= 8 ? root : root.appendingPathComponent(batchName)
            print("COMBINED REVIEW \(batchName): \(batchNames.count) images", terminator: "\n")
            try await reviewBatch(names: batchNames, directory: directory, root: batchRoot,
                                  environment: environment, frozen: frozen)
            batches.append(batchName)
        }
        if names.count > 8 {
            let summary = ["batches": batches, "files": names]
            try JSONEncoder().encode(summary).write(to: root.appendingPathComponent("diagnostic.json"), options: .atomic)
        }
    }

    @MainActor private func reviewBatch(names: [String], directory: URL, root: URL,
                                        environment: [String: String], frozen: Bool) async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = names.map { directory.appendingPathComponent($0) }
        for url in urls {
            try #require(FileManager.default.fileExists(atPath: url.path))
        }
        let modelURL = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_REVIEW_QWEN"]))
        let samURL = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_REVIEW_SAM3"]))
        let clipURL = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_REVIEW_CLIP"]))
        let runtime = QwenInferenceRuntime()
        try #require(await runtime.validate(url: modelURL).isAvailable)
        let segmentation = try ObjectSegmentationService(provider: CoreAISAM3Provider(modelBundleURL: samURL), stores: [], maxSide: 4320, maximumInstanceCount: 8)
        let clip = try CoreAICLIPProvider(modelBundleURL: clipURL)
        let backend = ReviewRecordingBackend(live: CombinedReviewLiveBackend(qwen: runtime, qwenURL: modelURL,
                                                                             segmentation: segmentation, samIdentity: samURL.path,
                                                                             clipProvider: clip, clipURL: clipURL))
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: root), lease: CombinedReviewLease(), backendFactory: { backend })
        feature.retainInputs = true
        feature.retainRejectedResponses = true
        await feature.analyze(urls.map { .init(id: UUID(), url: $0, name: $0.lastPathComponent) })
        await runtime.clear()
        let run = try #require(feature.manifest)
        struct Diagnostic: Encodable {
            let run: CombinedReviewRunV1
            let reports: [ReviewImageReport]
            let selection: ReviewSelectionReport?
            let responses: [ReviewProbeResponse]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let diagnostic = await Diagnostic(run: run, reports: feature.results.compactMap(\.report),
                                          selection: feature.selectionReport, responses: backend.responses)
        try encoder.encode(diagnostic).write(to: root.appendingPathComponent("diagnostic.json"), options: .atomic)
        #expect(feature.results.count == names.count)
        #expect(run.work.allSatisfy { $0.state.terminal })
        #expect(run.work.allSatisfy { $0.state == .completed })
        for (category, attempts) in run.budget.attempts {
            #expect(attempts <= run.budget.limits[category, default: 0])
        }
        for result in feature.results {
            #expect(result.overview != nil, "Discovery: \(result.file.displayName)")
            if frozen {
                #expect(!result.subjects.isEmpty, "Subject coverage: \(result.file.displayName)")
            }
            #expect(!result.clip.isEmpty)
            if frozen || !result.subjects.isEmpty {
                #expect(result.measurements.contains { $0.hasCurrentMaskSemantics })
                #expect(result.regions.contains { $0.subjectID != nil && $0.support?.subjectForegroundRetained == 1 })
            }
            if let report = result.report {
                for criterion in ["composition", "exposure", "visibility", "detail"] where !report.claims.contains(where: { $0.type == criterion }) {
                    #expect(report.incomplete)
                    #expect(report.limitations.contains { $0.id.rawValue == result.file.id.rawValue + ":coverage:" + criterion },
                            "Explicit abstention: \(result.file.displayName) \(criterion)")
                }
            } else {
                Issue.record("Missing synthesized report: \(result.file.displayName)")
            }
            for measurement in result.measurements where measurement.availability == .available {
                #expect(measurement.hasCurrentMaskSemantics)
                #expect(measurement.values.values.allSatisfy { $0.isFinite })
            }
        }
        let selection = try #require(feature.selectionReport)
        #expect(selection.cells.count == names.count)
        if frozen {
            #expect(selection.decision == .abstain)
            #expect(selection.preferred.isEmpty)
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_COMBINED_SELECTION_RUN"] == "1"))
    @MainActor func `six real Sony sources retain terminal reports and a bounded comparison`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_SELECTION_DIRECTORY"]))
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "arw" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        try #require(urls.count == 6)
        let modelURL = try URL(fileURLWithPath: #require(environment["RAWCULL_COMBINED_REVIEW_QWEN"]))
        let runtime = QwenInferenceRuntime()
        let status = await runtime.validate(url: modelURL)
        try #require(status.isAvailable)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CombinedSelectionProbe-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let backend = ReviewRecordingBackend(live: CombinedReviewLiveBackend(qwen: runtime, qwenURL: modelURL, segmentation: nil, samIdentity: nil, clipProvider: nil, clipURL: nil))
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: root), lease: CombinedReviewLease(), backendFactory: { backend })
        var sourceChecks: [[String: String]] = []
        for url in urls {
            let loader = ReviewImageSourceService()
            let availability = try await loader.availability(for: url)
            var row = ["file": url.lastPathComponent, "rawAdmission": availability.rawDisabledReason ?? "available", "previewAdmission": availability.previewDisabledReason ?? "available"]
            if availability.rawDisabledReason == nil {
                do {
                    let source = try await loader.load(.init(url: url, preference: .rawDetail, policy: .appearance))
                    row["rawDimensions"] = "\(source.image.width)x\(source.image.height)"
                    row["rawOrientation"] = String(source.metadata.originalOrientation)
                    let technical = try await loader.load(.init(url: url, preference: .rawDetail, policy: .technical))
                    let rect = CGRect(x: 100, y: 100, width: 512, height: 512)
                    _ = try source.mapSourceRect(rect, to: technical)
                    let region = try source.region(rect: rect, padding: 0, purpose: "RAW crop probe", encoder: .init(width: 448, height: 448, strategy: .stretch))
                    let crop = try source.crop(region)
                    row["rawCrop"] = "\(crop.width)x\(crop.height)"
                    row["technicalAlignment"] = "passed"
                } catch { row["rawDecodeFailure"] = String(describing: error) }
            }
            if let filter = CIRAWFilter(imageURL: url) {
                row["nativeDimensions"] = "\(Int(filter.nativeSize.width))x\(Int(filter.nativeSize.height))"
            }
            sourceChecks.append(row)
        }
        await feature.analyze(urls.map { .init(id: UUID(), url: $0, name: $0.lastPathComponent) })
        let run = try #require(feature.manifest)
        let report = try #require(feature.selectionReport)
        struct Diagnostic: Encodable {
            let run: CombinedReviewRunV1
            let sourceChecks: [[String: String]]
            let sources: [ReviewSourceRecord]
            let reports: [ReviewImageReport]
            let selection: ReviewSelectionReport
            let responses: [ReviewProbeResponse]
        }
        let diagnostic = await Diagnostic(run: run, sourceChecks: sourceChecks, sources: feature.results.compactMap(\.source), reports: feature.results.compactMap(\.report), selection: report, responses: backend.responses)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(diagnostic)
        Attachment.record(String(decoding: bytes, as: UTF8.self), named: "combined-selection-arw-probe.json")
        try bytes.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("combined-selection-arw-probe.json"), options: .atomic)
        #expect(feature.results.count == 6)
        #expect(feature.results.allSatisfy { $0.report != nil || !$0.failures.isEmpty })
        #expect(run.work.filter { $0.stage == .report }.allSatisfy { $0.state.terminal })
        #expect(run.budget.attempts[.overview] == 6)
        #expect(run.budget.attempts[.crop, default: 0] <= 16)
        #expect(run.budget.attempts[.comparison] == 1)
        #expect(await backend.responses.contains { $0.instruction.contains("Compare for goal:") })
        #expect(report.cells.count == 6 || run.work.contains { $0.stage == .comparison && $0.state == .failed })
        #expect(report.decision == .abstain) // No SAM/CLIP: incomplete technical evidence cannot support a winner.
        await runtime.clear()
    }
}

private nonisolated struct ProbeDiagnostic: Codable {
    let run: CombinedReviewRunV1
    let source: ReviewSourceRecord?
    let regions: [ReviewRegionRecord]
    let report: ReviewImageReport?
    let observations: [ReviewObservation]
    let failures: [String: String]
    let responses: [ReviewProbeResponse]
}

private nonisolated struct ReviewProbeResponse: Codable, Sendable {
    let instruction: String
    let width: Int
    let height: Int
    let text: String
}

private actor ReviewRecordingBackend: CombinedReviewBackendServing {
    let live: CombinedReviewLiveBackend
    var responses: [ReviewProbeResponse] = []

    init(live: CombinedReviewLiveBackend) {
        self.live = live
    }

    func models() async throws -> [String: ReviewModelSnapshot] {
        try await live.models()
    }

    func respond(instruction: String, image: CGImage, tokens: Int) async throws -> String {
        let text = try await live.respond(instruction: instruction, image: image, tokens: tokens)
        responses.append(.init(instruction: instruction, width: image.width, height: image.height, text: text))
        return text
    }

    func segment(image: CGImage, file: ReviewFileSnapshot, concept: String) async throws -> [ObjectInstanceDeduplicator.Candidate] {
        try await live.segment(image: image, file: file, concept: concept)
    }

    func clip(image: CGImage, criteria: String, model: ReviewModelSnapshot) async throws -> CombinedReviewCLIPResult {
        try await live.clip(image: image, criteria: criteria, model: model)
    }
}
