import Foundation
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
        let backend = CombinedReviewLiveBackend(qwen: runtime, qwenURL: modelURL, segmentation: nil, samIdentity: nil, clipProvider: nil, clipURL: nil)
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: root), lease: CombinedReviewLease(), backendFactory: { backend })
        await feature.analyze([.init(id: UUID(), url: imageURL, name: imageURL.lastPathComponent)])
        let result = try #require(feature.result)
        let run = try #require(feature.manifest)
        if let output = environment["RAWCULL_COMBINED_REVIEW_OUTPUT"] {
            let diagnostic = ProbeDiagnostic(run: run, report: result.report, observations: result.observations, failures: result.failures)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: output).lastPathComponent)
            try encoder.encode(diagnostic).write(to: outputURL, options: .atomic)
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
}

private nonisolated struct ProbeDiagnostic: Codable {
    let run: CombinedReviewRunV1
    let report: ReviewImageReport?
    let observations: [ReviewObservation]
    let failures: [String: String]
}
