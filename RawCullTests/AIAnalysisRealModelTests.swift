import CoreAICLIPBackend
import CoreAISAM3Backend
import CoreGraphics
import Foundation
import ImageIO
import PhotoAIContracts
import PhotoAIStorage
import PhotoAIWorkflows
@testable import RawCull
import RawCullCore
import Testing

/// Opt-in diagnostics through the same features as the three analysis tabs.
@Suite("AI Analysis installed-model diagnostics")
struct AIAnalysisRealModelTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RAWCULL_ANALYSIS_RUN"] == "1"))
    @MainActor func `selected ARWs run SAM CLIP then Qwen then Objects`() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = try URL(fileURLWithPath: #require(env["RAWCULL_ANALYSIS_OUTPUT"]))
        try #require(!FileManager.default.fileExists(atPath: root.path))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let directory = try URL(fileURLWithPath: #require(env["RAWCULL_ANALYSIS_DIRECTORY"]))
        let names = try JSONDecoder().decode([String].self, from: Data(#require(env["RAWCULL_ANALYSIS_NAMES"]).utf8))
        try #require((1...6).contains(names.count) && Set(names).count == names.count)
        try #require(names.allSatisfy { URL(fileURLWithPath: $0).lastPathComponent == $0 && $0.lowercased().hasSuffix(".arw") })
        let files = try names.map { name in
            let url = directory.appendingPathComponent(name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return FileItem(id: UUID(), url: url, name: name, size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
                            dateModified: (attributes[.modificationDate] as? Date) ?? .distantPast, exifData: nil, afFocusNormalized: nil)
        }
        // Private runtime and stores prevent using the application's cached results.
        let recording = AnalysisRecordingInference(root: root)
        let runtime = RawCullAIModelRuntime(paths: .init(applicationSupportRoot: root, cachesRoot: root), qwenInference: recording)
        let deep = DeepAIReviewFeature()
        runtime.bindDeepAIReviewFeature(deep)
        let qwen = try URL(fileURLWithPath: #require(env["RAWCULL_ANALYSIS_QWEN"]))
        let sam = try URL(fileURLWithPath: #require(env["RAWCULL_ANALYSIS_SAM3"]))
        let clipURL = try URL(fileURLWithPath: #require(env["RAWCULL_ANALYSIS_CLIP"]))
        let status = await runtime.applyManagedModelLocations([.sam3: sam, .clipDataComp: clipURL, .qwen3VL2B: qwen])
        let capabilities = try await runtime.refreshCapabilities()
        try writeDump(capabilities, to: root.appendingPathComponent("models.txt"))
        var summary: [[String: String]] = []
        for stage in ["sam-clip", "qwen", "objects"] {
            await recording.setStage(stage)
            for (index, file) in files.enumerated() {
                print("AI ANALYSIS stage=\(stage) image=\(index + 1)/\(files.count) file=\(file.name)")
                let start = Date()
                var failure: String?
                let output = root.appendingPathComponent("\(stage)-\(index + 1).txt")
                do {
                    switch stage {
                    case "sam-clip":
                        let signature = BurstGroupSignature(memberKeys: [file.name])
                        await deep.start(.init(groupID: index, groupSignature: signature,
                            candidates: [.init(fileID: file.id, fileName: file.name, url: file.url, burstRank: 1,
                                               normalSharpnessScore: nil, subjectLabel: nil, normalizedAFPoint: nil)],
                            preset: .auto, scoringSource: .embeddedPreview))
                        try writeDump(deep.state, to: output)
                        if deep.completedCandidates.first(where: { $0.fileID == file.id })?.isCompleted != true {
                            failure = "SAM analysis did not complete; see state dump"
                        }
                        // The tab's Deep Review pipeline does not invoke CLIP. Record a separate
                        // real CLIP embedding probe explicitly rather than imply it did.
                        let provider = try CoreAICLIPProvider(modelBundleURL: clipURL)
                        let image = try #require(await RawParserKitImageLoader.shared.thumbnailCGImage(for: file.url, maxPixelSize: 2048))
                        let embedding = try await provider.embedding(for: image).values
                        try writeDump(embedding, to: root.appendingPathComponent("clip-\(index + 1).txt"))
                        #expect(!embedding.isEmpty && embedding.allSatisfy(\.isFinite))
                    case "qwen":
                        let feature = RawCullQwenAnalysisFeature(inference: recording)
                        feature.updateModelStatus(status)
                        await feature.analyze([file])
                        try writeDump(feature.results, to: output)
                        failure = feature.results.first?.failure ?? (feature.results.isEmpty ? "No Qwen result" : nil)
                    default:
                        let feature = RawCullObjectAnalysisFeature(inference: recording, maskStores: [runtime.objectMaskMemoryStore])
                        feature.install(segmentation: runtime.objectSegmentation, qwenStatus: status)
                        await feature.analyze([file])
                        try writeDump(feature.results, to: output)
                        failure = feature.results.first?.failure ?? (feature.results.isEmpty ? "No Objects result" : nil)
                    }
                } catch {
                    failure = String(describing: error)
                    try writeDump(failure, to: output)
                }
                let row = ["stage": stage, "file": file.name, "elapsedSeconds": String(Date().timeIntervalSince(start)),
                           "failure": failure ?? "", "result": output.lastPathComponent]
                summary.append(row)
                try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
                    .write(to: root.appendingPathComponent("progress.json"), options: .atomic)
                if let failure { Issue.record("\(stage) \(file.name): \(failure)") }
            }
        }
        await recording.clear()
        try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("diagnostic.json"), options: .atomic)
        #expect(summary.count == files.count * 3)
    }
}

private func writeDump(_ value: Any, to url: URL) throws {
    var text = ""
    dump(value, to: &text, maxDepth: .max, maxItems: .max)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private actor AnalysisRecordingInference: QwenInferenceServing {
    let live = QwenInferenceRuntime()
    let root: URL
    var stage = "setup"
    var sequence = 0
    init(root: URL) { self.root = root }
    func setStage(_ value: String) { stage = value }
    func validate(url: URL) async -> QwenModelStatus { await live.validate(url: url) }
    func inputCapabilities() async -> QwenInputCapabilities? { await live.inputCapabilities() }
    func clear() async { await live.clear() }
    func assess(criteria: String, image: CGImage) async throws -> QwenModelResponse {
        try await QwenModelResponse.decode(respond(to: .init(instruction: QwenInferenceRuntime.assessmentInstruction(criteria: criteria),
                                                           image: image, maximumResponseTokens: 512)))
    }
    func respond(to request: QwenVisionRequest) async throws -> String {
        sequence += 1
        let prefix = root.appendingPathComponent("\(stage)-request-\(sequence)")
        try writeDump(["instruction": request.instruction, "tokens": String(request.maximumResponseTokens),
                       "width": String(request.image.width), "height": String(request.image.height)],
                      to: prefix.appendingPathExtension("txt"))
        let destination = try #require(CGImageDestinationCreateWithURL(prefix.appendingPathExtension("png") as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, request.image, nil)
        try #require(CGImageDestinationFinalize(destination))
        do {
            let response = try await live.respond(to: request)
            try response.write(to: prefix.appendingPathExtension("response.txt"), atomically: true, encoding: .utf8)
            return response
        } catch {
            try String(describing: error).write(to: prefix.appendingPathExtension("error.txt"), atomically: true, encoding: .utf8)
            throw error
        }
    }
}
