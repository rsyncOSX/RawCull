import CoreAICLIPBackend
import CoreGraphics
import CryptoKit
import Foundation
import PhotoAIContracts
import PhotoAIWorkflows

/// Captured provider values are immutable for the run. Qwen keeps its existing
/// generation gate; the feature additionally reserves sibling AI workflows.
nonisolated struct CombinedReviewLiveBackend: CombinedReviewBackendServing {
    let qwen: any QwenInferenceServing
    let qwenURL: URL
    let segmentation: ObjectSegmentationService?
    let samIdentity: String?
    let clipProvider: CoreAICLIPProvider?
    let clipURL: URL?

    @concurrent
    func models() async throws -> [String: ReviewModelSnapshot] {
        guard let capability = await qwen.inputCapabilities(), capability.configuredEncoderSide == 448,
              capability.configuredImageStrategy == "stretch", capability.maximumContextTokens == 4096,
              capability.configuredImageTokens == 196 else { throw ReviewRunError.modelUnavailable }
        let hash = try await Self.bundleHash(qwenURL)
        guard hash == "8b575d2b2a499c2ea697deb7f878eee7afdc79818c95d9e304eb7809242d19f7" else {
            throw ReviewRunError.modelUnavailable
        }
        let version = "coreai-1953c4f-photoaikit-7f9adfc|\(ProcessInfo.processInfo.operatingSystemVersionString)"
        var models = ["qwen": ReviewModelSnapshot(identity: hash, runtimeVersion: version,
                                                  preprocessing: "stretch RGB sRGB NCHW mean/std0.5 rescale1", encoderWidth: 448, encoderHeight: 448,
                                                  contextTokens: 4096, imageTokens: 196)]
        if segmentation != nil, let samIdentity {
            models["sam"] = .init(identity: samIdentity, runtimeVersion: version, preprocessing: "PhotoAIKit SAM3 source-normalized masks maxSide4320",
                                  encoderWidth: 0, encoderHeight: 0, contextTokens: nil, imageTokens: nil)
        }
        if let clipProvider, let clipURL {
            let clipHash = try? await Self.bundleHash(clipURL)
            try Task.checkCancellation()
            let side: Int? = switch clipHash {
            case "ac42a2db447f60cd0d0e3e8a31e6dec2ca29f85e6637e84f8fee44bf19ce91d1": 224
            case "796848121936bde228b1cc14471baae1ba7c12d1beaee30cff7bf1bae847c6a5": 256
            default: nil
            }
            if let side, let clipHash {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
                let descriptor = try encoder.encode(RawCullCLIPInputCapabilities(provider: clipProvider))
                models["clip"] = .init(identity: clipHash, runtimeVersion: version,
                                       preprocessing: String(decoding: descriptor, as: UTF8.self), encoderWidth: side, encoderHeight: side,
                                       contextTokens: nil, imageTokens: nil)
            }
        }
        return models
    }

    func respond(instruction: String, image: CGImage, tokens: Int) async throws -> String {
        try await qwen.respond(to: .init(instruction: instruction, image: image, maximumResponseTokens: tokens))
    }

    func segment(image: CGImage, file: ReviewFileSnapshot, concept: String) async throws -> [ObjectInstanceDeduplicator.Candidate] {
        guard let segmentation else { throw ReviewRunError.modelUnavailable }
        let query = try SegmentationConcept(concept)
        let result = try await segmentation.segment(image: image,
                                                    source: AIImageSource(id: file.fileID, url: file.url, displayName: file.displayName), concept: query)
        return result.instances.map { .init(concept: query, mask: $0.mask, score: $0.score,
                                            normalizedBoundingBox: $0.normalizedBoundingBox, sourceInstanceID: $0.id) }
    }

    func clip(image: CGImage, criteria: String, model: ReviewModelSnapshot) async throws -> CombinedReviewCLIPResult {
        guard let provider = clipProvider, clipURL != nil else { throw ReviewRunError.modelUnavailable }
        let visual = try await provider.embedding(for: image).values
        let text = try await provider.embedding(for: criteria).values
        guard visual.count == text.count, !visual.isEmpty, visual.allSatisfy(\.isFinite), text.allSatisfy(\.isFinite) else {
            throw ReviewRunError.invalidEvidence
        }
        let dot = zip(visual, text).reduce(Float.zero) { $0 + $1.0 * $1.1 }
        let norm = sqrt(visual.reduce(0) { $0 + $1 * $1 } * text.reduce(0) { $0 + $1 * $1 })
        guard norm.isFinite, norm > 0 else { throw ReviewRunError.invalidEvidence }
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let trace = try ReviewEncoderGeometry(width: model.encoderWidth, height: model.encoderHeight, strategy: .shortestSideCenterCrop).trace(crop: bounds)
        return .init(relevance: dot / norm, embedding: visual, model: model, geometry: .init(inputSize: bounds.size,
                                                                                             retainedInputRect: trace.retainedSourceRect, encoderSize: trace.encoderSize, scaleX: Double(trace.scaleX), scaleY: Double(trace.scaleY)))
    }

    @concurrent
    static func bundleHash(_ root: URL) async throws -> String {
        try hashSynchronously(root)
    }

    private static func hashSynchronously(_ root: URL) throws -> String {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            throw ReviewRunError.modelUnavailable
        }
        var files: [URL] = []
        for case let file as URL in enumerator {
            try Task.checkCancellation()
            if try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files.append(file)
            }
        }
        var tree = SHA256()
        for file in files.sorted(by: { $0.path < $1.path }) {
            try Task.checkCancellation()
            let relative = String(file.path.dropFirst(root.path.count + 1))
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
                try Task.checkCancellation(); hash.update(data: bytes)
            }
            let hex = hash.finalize().map { String(format: "%02x", $0) }.joined()
            tree.update(data: Data("\(relative)\0\(hex)\n".utf8))
        }
        return tree.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
