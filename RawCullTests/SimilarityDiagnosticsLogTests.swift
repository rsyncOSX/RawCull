import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

private nonisolated let diagnosticsTestBackend = SimilarityBackendDescriptor(
    backend: "clip",
    modelFingerprint: "diagnostics-test-clip-v1",
    representation: "float-vector",
    preprocessingVersion: "diagnostics-test-v1",
    normalizationVersion: "l2-v1",
    configurationVersion: "diagnostics-test-v1",
)

@Suite("Similarity diagnostics log")
struct SimilarityDiagnosticsLogTests {
    @Test
    func `persists the failed image, stage, and reason`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimilarityDiagnosticsLog-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let logURL = directory.appendingPathComponent("Similarity.log")
        let log = SimilarityDiagnosticsLog(fileURL: logURL)
        let imageURL = URL(fileURLWithPath: "/catalog/session/image-042.ARW")
        let source = AIImageSource(
            id: UUID(),
            url: imageURL,
            displayName: imageURL.lastPathComponent,
        )
        let failure = RawCullCLIPPrimaryFailure(
            source: source,
            stage: .clipInference,
            message: "Core ML execution failed in the release process",
        )
        let event = SimilarityDiagnosticsEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            backend: diagnosticsTestBackend,
            requestedImageCount: 574,
            thumbnailMaxPixelSize: 512,
            summary: "CLIP failed for image-042.ARW",
            outcome: .visionFallback(
                artifactsCreated: 574,
                clipFailures: [failure],
                visionFailures: [],
                validationFailures: [],
            ),
        )

        try await log.record(event)
        let contents = try await log.contents()

        #expect(contents.contains("Outcome: CLIP failed; used whole-batch Vision fallback"))
        #expect(contents.contains("Requested images: 574"))
        #expect(contents.contains("Image: image-042.ARW"))
        #expect(contents.contains("URL: /catalog/session/image-042.ARW"))
        #expect(contents.contains("Stage: CLIP inference"))
        #expect(contents.contains("Reason: Core ML execution failed in the release process"))

        try await log.clear()
        let clearedContents = try await log.contents()
        #expect(clearedContents.isEmpty)
    }
}
