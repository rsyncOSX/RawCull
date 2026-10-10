import CoreGraphics
import Foundation
import PhotoAIContracts
@testable import RawCull
import Testing

@Suite("Single-image Combined Review", .tags(.smoke))
struct CombinedReviewFeatureTests {
    @Test @MainActor func `degraded review keeps crops grounded and inspectable`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend()
        let feature = makeFeature(fixture, backend: backend)
        await feature.analyze([fixture.file])
        let result = try #require(feature.result)
        let report = try #require(result.report)
        #expect(!report.claims.isEmpty)
        #expect(report.incomplete)
        #expect(result.measurements.isEmpty)
        #expect(result.regions.count == 1)
        #expect(result.limitations.contains { $0.reason.contains("Eye localization unavailable") })
        let inputKey = try #require(result.regions.first?.inputReference)
        let input = await feature.exactInput(inputKey)
        #expect(input?.width == 128)
        #expect(feature.manifest?.budget.attempts[.crop] == 1)
        #expect(!feature.lease.isHeld)
        #expect(!feature.isRunning)
    }

    @Test @MainActor func `SAM and technical scorer supply separate measured evidence`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend(hasSAM: true)
        let feature = makeFeature(fixture, backend: backend)
        await feature.analyze([fixture.file])
        let result = try #require(feature.result)
        #expect(result.subjects.count == 1)
        #expect(result.measurements.count == 1)
        #expect(result.regions.count >= 1)
        #expect(result.measurements.first?.provenance.renderPolicy == "technical")
        #expect(result.observations.filter { $0.regionID != nil }.allSatisfy { $0.provenance.renderPolicy == "appearance" })
        #expect(feature.manifest?.work.filter { $0.stage == .report }.allSatisfy { $0.state == .completed } == true)
        let evidenceIDs = Set(result.observations.map { $0.id.rawValue } + result.measurements.map { $0.id.rawValue })
        let report = try #require(result.report)
        #expect(report.claims.flatMap(\.evidence).allSatisfy { evidenceIDs.contains($0.id) })
        #expect(report.claims.flatMap(\.evidence).allSatisfy { !$0.id.hasPrefix("o") && !$0.id.hasPrefix("m") })
        #expect(report.claims.flatMap(\.evidence).allSatisfy { !$0.id.contains(":reconcile") })
    }

    @Test @MainActor func `malformed crop output is a failure and cannot become detail`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend(invalidCrop: true))
        await feature.analyze([fixture.file])
        let result = try #require(feature.result)
        #expect(result.observations.filter { $0.regionID != nil }.isEmpty)
        #expect(result.report?.uninspectedRegions.count == 1)
        #expect(feature.manifest?.work.contains { $0.stage == .cropObservation && $0.state == .failed } == true)
        #expect(feature.manifest?.budget.attempts[.crop] == 1)
    }

    @Test @MainActor func `unknown report reference causes explicit partial report`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend(invalidReport: true))
        await feature.analyze([fixture.file])
        #expect(feature.result?.report?.claims.isEmpty == true)
        #expect(feature.result?.observations.count == 2)
        #expect(feature.manifest?.work.contains { $0.stage == .report && $0.state == .failed } == true)
    }

    @Test @MainActor func `cancellation retains completed overview and resume spends no free retry`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend(delayCrop: true)
        let feature = makeFeature(fixture, backend: backend)
        let task = Task { await feature.analyze([fixture.file]) }
        for _ in 0 ..< 300 {
            if await backend.cropStarted {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await backend.cropStarted)
        feature.lease.invalidate()
        #expect(feature.lease.isHeld)
        await backend.stopDelay()
        await task.value
        #expect(feature.manifest?.work.contains { $0.stage == .overview && $0.state == .completed } == true)
        #expect(feature.manifest?.budget.attempts[.crop] == 1)
        #expect(!feature.lease.isHeld)
        await backend.stopDelay()
        await feature.resume()
        #expect(feature.manifest?.budget.attempts[.overview] == 1)
        #expect(feature.manifest?.budget.attempts[.crop] == 2)
        #expect(feature.result?.report != nil)
        #expect(feature.manifest?.cancelled == false)
    }

    @Test @MainActor func `stored results restore without new inference and changed files refuse resume`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend(), original = makeFeature(fixture, backend: backend)
        await original.analyze([fixture.file])
        let calls = await backend.responses
        let restored = makeFeature(fixture, backend: backend)
        await restored.restoreStoredRun()
        await restored.resume()
        #expect(await backend.responses == calls)
        #expect(restored.result?.report != nil)
        try Data("changed".utf8).write(to: fixture.file.url)
        await restored.resume()
        #expect(restored.failureMessage?.contains("Resume unavailable") == true)
        #expect(await backend.responses == calls)
    }

    @Test @MainActor func `region settings are frozen and compact retention is explicit`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        feature.userRegion = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        feature.retainInputs = false
        await feature.analyze([fixture.file])
        #expect(feature.result?.regions.first?.requestedRect.width == 64)
        #expect(feature.result?.regions.first?.inputReference == nil)
        #expect(feature.manifest?.snapshot.userRegions?.count == 1)
        feature.userRegion = nil
        #expect(feature.manifest?.snapshot.userRegions?.count == 1)
    }

    @Test func `structured responses reject changed IDs and unsupported eye detail`() throws {
        #expect(throws: (any Error).self) { try CombinedReviewResponse.inspection("{\"regionID\":\"other\",\"observations\":\"visible\",\"uncertainty\":\"limited\",\"insufficientEvidence\":false}", regionID: "expected") }
        let ref = ReviewEvidenceReference(kind: .observation, id: "known")
        let response = "{\"claims\":[{\"text\":\"Sharp eye detail\",\"type\":\"detail\",\"evidence\":[{\"kind\":\"observation\",\"id\":\"known\"}],\"uncertainty\":\"limited\",\"contradictions\":[]}]}"
        #expect(throws: (any Error).self) { try CombinedReviewResponse.report(response, imageID: .init(rawValue: "image"), allowed: [ref], limitations: [], regions: [], uninspected: [], incomplete: true) }
        #expect(throws: ReviewRunError.self) { try CombinedReviewResponse.admitted(String(repeating: "x", count: 4096), model: ReviewFakeBackend.qwen, outputTokens: 768) }
    }

    @Test @MainActor func `lease stays reserved until worker acknowledges invalidation`() throws {
        let lease = CombinedReviewLease(), id = UUID()
        var cancelled = false
        try lease.acquire(id); lease.invalidateOwner = { cancelled = true }
        lease.invalidate()
        #expect(cancelled && lease.isHeld)
        #expect(throws: ReviewRunError.self) { try lease.acquire(UUID()) }
        lease.release(UUID()); #expect(lease.isHeld)
        lease.release(id); #expect(!lease.isHeld)
    }

    @Test @MainActor func `source refusal explains preview rerun and resume keeps saved source`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend()
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: fixture.root.appendingPathComponent("store")),
                                            sourceLoader: ReviewPreviewOnlySource(), lease: CombinedReviewLease(), backendFactory: { backend })
        feature.sourcePreference = .rawDetail
        await feature.analyze([fixture.file])
        let refusedRun = try #require(feature.manifest)
        #expect(feature.failureMessage?.contains("High-quality preview") == true)
        #expect(feature.failureMessage?.contains("Rerun with current settings") == true)
        #expect(await backend.responses == 0)
        #expect(!feature.isRunning && !feature.lease.isHeld)

        feature.sourcePreference = .highQualityPreview
        await feature.resume()
        #expect(feature.manifest?.snapshot.sourcePreference == ReviewSourcePreference.rawDetail.rawValue)
        #expect(feature.failureMessage?.contains("Resume keeps the saved source setting") == true)
        #expect(feature.progress == "Resume stopped — rerun with current settings")
        #expect(await backend.responses == 0)

        await feature.analyze([fixture.file])
        #expect(feature.manifest?.snapshot.id != refusedRun.snapshot.id)
        #expect(feature.manifest?.snapshot.sourcePreference == ReviewSourcePreference.highQualityPreview.rawValue)
        #expect(feature.result?.report?.claims.isEmpty == false)
        #expect(feature.failureMessage == nil)
        #expect(!feature.isRunning && !feature.lease.isHeld)
    }

    private struct Fixture { let root: URL; let file: ReviewSelectedFile }
    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("fixture.png")
        let context = try #require(CGContext(data: nil, width: 128, height: 96, bitsPerComponent: 8, bytesPerRow: 512,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 0.5, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 128, height: 96))
        let image = try #require(context.makeImage())
        try ReviewImageSource.pngData(for: image).write(to: url)
        return .init(root: root, file: .init(id: UUID(), url: url, name: "fixture.png"))
    }

    @MainActor private func makeFeature(_ fixture: Fixture, backend: ReviewFakeBackend) -> CombinedReviewFeature {
        CombinedReviewFeature(store: ReviewArtifactStore(root: fixture.root.appendingPathComponent("store")),
                              scorer: ReviewFakeScorer(), lease: CombinedReviewLease(), backendFactory: { backend })
    }
}

private nonisolated struct ReviewPreviewOnlySource: ReviewImageSourceLoading {
    func load(_ request: ReviewSourceRequest) async throws -> ReviewImageSource {
        guard request.preference == .highQualityPreview else { throw ReviewImageError.memoryAdmissionDenied }
        return try await ReviewImageSourceService().load(request)
    }
}

private actor ReviewFakeBackend: CombinedReviewBackendServing {
    nonisolated static let qwen = ReviewModelSnapshot(identity: "fake", runtimeVersion: "test", preprocessing: "stretch", encoderWidth: 448, encoderHeight: 448, contextTokens: 4096, imageTokens: 196)
    let hasSAM: Bool, invalidCrop: Bool, invalidReport: Bool
    var delayCrop: Bool
    var cropContinuation: CheckedContinuation<Void, Never>?
    var cropStarted = false
    var responses = 0
    init(hasSAM: Bool = false, invalidCrop: Bool = false, invalidReport: Bool = false, delayCrop: Bool = false) {
        self.hasSAM = hasSAM; self.invalidCrop = invalidCrop; self.invalidReport = invalidReport; self.delayCrop = delayCrop
    }

    func stopDelay() {
        delayCrop = false
    }

    func models() -> [String: ReviewModelSnapshot] {
        var models = ["qwen": Self.qwen]
        if hasSAM {
            models["sam"] = .init(identity: "SAM", runtimeVersion: "test", preprocessing: "test", encoderWidth: 0, encoderHeight: 0, contextTokens: nil, imageTokens: nil)
        }
        return models
    }

    func respond(instruction: String, image _: CGImage, tokens _: Int) async throws -> String {
        responses += 1
        if instruction.contains("concepts") {
            return "{\"observations\":\"Centered visible subject\",\"uncertainty\":\"Overview lacks fine detail\",\"concepts\":[{\"query\":\"bird\",\"displayName\":\"Bird\",\"reason\":\"Visible subject\"}]}"
        }
        if let line = instruction.split(separator: "\n").first(where: { $0.contains("Region ID:") }) {
            cropStarted = true
            if delayCrop {
                try await Task.sleep(for: .seconds(30))
            }
            if invalidCrop {
                return "not JSON"
            }
            let region = line.components(separatedBy: "Region ID: ")[1].components(separatedBy: ". Purpose:")[0]
            return "{\"regionID\":\"\(region)\",\"observations\":\"Visible texture in crop\",\"uncertainty\":\"Eye identity unknown\",\"insufficientEvidence\":false}"
        }
        let reference = instruction.split(separator: "\n").compactMap { line -> ReviewEvidenceReference? in
            guard let end = line.firstIndex(of: "}") else { return nil }
            return try? JSONDecoder().decode(ReviewEvidenceReference.self, from: Data(line[...end].utf8))
        }.first { $0.kind == .observation }
        let ref = invalidReport ? ReviewEvidenceReference(kind: .observation, id: "invented") : reference ?? .init(kind: .observation, id: "missing")
        let claim = ReviewClaim(text: "Visible subject has texture", type: "composition", evidence: [ref], uncertainty: "Eye detail is unverified", contradictions: [])
        return try String(decoding: JSONEncoder().encode(["claims": [claim]]), as: UTF8.self)
    }

    func segment(image: CGImage, file _: ReviewFileSnapshot, concept: String) throws -> [ObjectInstanceDeduplicator.Candidate] {
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                                             space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: image.width / 4, y: image.height / 4, width: image.width / 2, height: image.height / 2))
        let mask = try #require(context.makeImage())
        return try [.init(concept: SegmentationConcept(concept), mask: mask, score: 0.9,
                          normalizedBoundingBox: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))]
    }

    func clip(image _: CGImage, criteria _: String, model _: ReviewModelSnapshot) throws -> CombinedReviewCLIPResult {
        throw ReviewRunError.modelUnavailable
    }
}

private nonisolated struct ReviewFakeScorer: SubjectMaskFocusScoring {
    func score(image _: CGImage, subjectMask _: CGImage, normalizedAFPoint _: CGPoint?) async throws -> SubjectMaskFocusEvidence? {
        .init(finalScore: 0.5, broadSubjectScore: 0.4, localDetailScore: 0.5, fineDetailScore: 0.6, maskCoverage: 0.25,
              autofocusInsideMask: nil, usableLocalPatch: true, backgroundDominancePenaltyApplied: false)
    }
}
