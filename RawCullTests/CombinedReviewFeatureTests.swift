import CoreGraphics
import Foundation
import PhotoAIContracts
@testable import RawCull
import RawParserKit
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
        #expect(restored.resumeDisabledReason != nil)
        #expect(restored.failureMessage == nil)
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

    @Test @MainActor func `complete cleanup removes review storage and history and allows a fresh run`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        await feature.analyze([fixture.file])
        let previous = try #require(feature.manifest?.snapshot.id)
        #expect(try await feature.store.usage() > 0)
        try await feature.clearAllReviews()
        #expect(feature.result == nil)
        #expect(feature.manifest == nil)
        #expect(feature.taskHistory.isEmpty)
        #expect(feature.failureMessage == nil)
        #expect(!feature.lease.isHeld)
        #expect(!FileManager.default.fileExists(atPath: feature.store.root.path))
        #expect(FileManager.default.fileExists(atPath: fixture.file.url.path))
        await feature.restoreStoredRun()
        #expect(feature.manifest == nil)
        try await feature.clearAllReviews()
        #expect(try await feature.store.usage() == 0)
        await feature.analyze([fixture.file])
        #expect(feature.manifest?.snapshot.id != previous)
        #expect(feature.result?.report != nil)
    }

    @Test @MainActor func `cleanup refuses an active review reservation without deleting files`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        await feature.analyze([fixture.file])
        let reservation = UUID()
        try feature.lease.acquire(reservation)
        defer { feature.lease.release(reservation) }
        await #expect(throws: ReviewRunError.self) { try await feature.clearAllReviews() }
        #expect(feature.manifest != nil)
        #expect(try await feature.store.usage() > 0)
        #expect(feature.lease.owner == reservation)
    }

    @Test @MainActor func `selection reviews every image before unrelated synthesis and restores without inference`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend()
        let feature = makeFeature(fixture, backend: backend)
        var files = [fixture.file]
        for index in 1 ... 5 {
            let url = fixture.root.appendingPathComponent("image-\(index).png")
            try FileManager.default.copyItem(at: fixture.file.url, to: url)
            files.append(.init(id: UUID(), url: url, name: url.lastPathComponent))
        }
        await feature.analyze(files.reversed())
        #expect(feature.results.count == 6)
        #expect(feature.results.allSatisfy { $0.report != nil })
        #expect(feature.selectionReport?.comparability == .unrelated)
        #expect(feature.selectionReport?.decision == .abstain)
        #expect(feature.selectionReport?.preferred.isEmpty == true)
        #expect(feature.selectionReport?.cells.count == 6)
        #expect(feature.manifest?.budget.attempts[.overview] == 6)
        #expect(feature.manifest?.budget.attempts[.report] == 6)
        #expect(feature.manifest?.budget.attempts[.comparison] == 1)
        let manifest = try #require(feature.manifest)
        try manifest.validate()
        let selection = try #require(manifest.work.first { $0.stage == .comparison })
        #expect(selection.dependencies.count == 6)
        let responses = await backend.responses
        let restored = makeFeature(fixture, backend: backend)
        await restored.restoreStoredRun(); await restored.resume()
        #expect(restored.results.count == 6)
        #expect(restored.selectionReport?.comparability == .unrelated)
        #expect(await backend.responses == responses)
        #expect(restored.manifest?.budget.attempts == manifest.budget.attempts)
        try Data("changed".utf8).write(to: files[5].url)
        await restored.resume()
        #expect(restored.resumeDisabledReason != nil)
    }

    @Test @MainActor func `missing image stage cannot prevent other reports or force comparison`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let broken = fixture.root.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: broken)
        let backend = ReviewFakeBackend()
        let feature = CombinedReviewFeature(store: ReviewArtifactStore(root: fixture.root.appendingPathComponent("store")),
                                            sourceLoader: ReviewPreviewOnlySource(), lease: CombinedReviewLease(), backendFactory: { backend })
        await feature.analyze([fixture.file, .init(id: UUID(), url: broken, name: "broken.png")])
        #expect(feature.results.count == 2)
        #expect(feature.results.contains { $0.report != nil })
        #expect(feature.results.contains { !$0.failures.isEmpty })
        #expect(feature.selectionReport?.decision == .abstain)
        #expect(feature.selectionReport?.comparability == .insufficient)
        #expect(feature.manifest?.work.filter { $0.stage == .report }.allSatisfy { $0.state.terminal } == true)
    }

    @Test @MainActor func `comparison rejects subject image swaps and accepts supported ties`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let url = fixture.root.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: fixture.file.url, to: url)
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        await feature.analyze([fixture.file, .init(id: UUID(), url: url, name: "second.png")])
        var values = feature.results
        for index in values.indices {
            let old = try #require(values[index].report)
            values[index].report = .init(id: old.id, imageID: old.imageID, claims: old.claims, limitations: [], incomplete: false, inspectedRegions: old.inspectedRegions, uninspectedRegions: [])
        }
        let left = values[0], right = values[1]
        let leftRef = try ReviewEvidenceReference(kind: .observation, id: #require(left.observations.first).id.rawValue)
        let rightRef = try ReviewEvidenceReference(kind: .observation, id: #require(right.observations.first).id.rawValue)
        let claim = ReviewClaim(text: "Both frames show left centered subject", type: "composition", evidence: [leftRef, rightRef], uncertainty: "Aesthetic tie", contradictions: [])
        let tie = ReviewSelectionReport(comparability: .comparable, decision: .tie, preferred: [left.file.id, right.file.id], claims: [.init(imageIDs: [left.file.id, right.file.id], claim: claim)], reason: "No supported preference")
        try tie.validate(results: values)
        let conflicted = ReviewSelectionReport(comparability: .comparable, decision: .preferred, preferred: [left.file.id],
                                               claims: [.init(imageIDs: [left.file.id, right.file.id], claim: .init(text: "Composition preference", type: "composition", evidence: [leftRef, rightRef], uncertainty: "Conflicting criteria", contradictions: [rightRef]))], reason: "Unresolved conflict")
        #expect(throws: ReviewRunError.self) { try conflicted.validate(results: values) }
        let uncovered = ReviewSelectionReport(comparability: .comparable, decision: .preferred, preferred: [left.file.id],
                                              claims: [.init(imageIDs: [left.file.id], claim: .init(text: "Centered composition", type: "composition", evidence: [leftRef], uncertainty: "No evidence for the other image", contradictions: []))], reason: "Preference without comparison coverage")
        #expect(throws: ReviewRunError.self) { try uncovered.validate(results: values) }
        let swapped = ReviewSelectionReport(comparability: .comparable, decision: .preferred, preferred: [right.file.id], claims: [.init(imageIDs: [right.file.id], claim: .init(text: "Centered subject", type: "composition", evidence: [leftRef], uncertainty: "limited", contradictions: []))], reason: "Preference")
        #expect(throws: ReviewRunError.self) { try swapped.validate(results: values) }
        var missing = values; missing[1].report = nil
        #expect(throws: ReviewRunError.self) { try tie.validate(results: missing) }
        let unrelated = ReviewSelectionReport(comparability: .unrelated, decision: .preferred, preferred: [left.file.id], claims: [], reason: "Different scenes")
        #expect(throws: ReviewRunError.self) { try unrelated.validate(results: values) }
    }

    @Test @MainActor func `eight image comparison preserves mandatory context coverage`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backend = ReviewFakeBackend()
        let feature = makeFeature(fixture, backend: backend)
        var files = [fixture.file]
        for index in 1 ... 7 {
            let url = fixture.root.appendingPathComponent("image-\(index).png")
            try FileManager.default.copyItem(at: fixture.file.url, to: url)
            files.append(.init(id: UUID(), url: url, name: url.lastPathComponent))
        }
        await feature.analyze(files)
        #expect(feature.results.count == 8)
        #expect(feature.selectionReport?.comparability == .unrelated)
        #expect(feature.selectionReport?.cells.count == 8)
        #expect(feature.manifest?.work.last(where: { $0.stage == .comparison })?.state == .completed)
        var snapshot = try #require(feature.manifest?.snapshot)
        let original = try ReviewCompatibility.make(snapshot: snapshot, image: snapshot.files[0], stage: .comparison)
        let changedFiles = Array(snapshot.files.dropLast())
        snapshot = .init(id: snapshot.id, files: changedFiles, criteria: snapshot.criteria, depth: snapshot.depth, sourcePreference: snapshot.sourcePreference,
                         retentionPolicy: snapshot.retentionPolicy, renderVersion: snapshot.renderVersion, models: snapshot.models, stageVersions: snapshot.stageVersions,
                         responseTokens: snapshot.responseTokens, pipelineVersion: snapshot.pipelineVersion, created: snapshot.created, expandedSelectionPlan: nil)
        let changed = try ReviewCompatibility.make(snapshot: snapshot, image: snapshot.files[0], stage: .comparison)
        #expect(original != changed)
    }

    @Test(arguments: [2, 4]) @MainActor func `deep ties use capped matched pairs without overriding the selection tie`(count: Int) async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let url = fixture.root.appendingPathComponent("second.png")
        try FileManager.default.copyItem(at: fixture.file.url, to: url)
        let backend = ReviewFakeBackend(hasSAM: true, hasCLIP: true, comparisonTie: true)
        let feature = makeFeature(fixture, backend: backend)
        feature.depth = .deep
        var files = [fixture.file, ReviewSelectedFile(id: UUID(), url: url, name: "second.png")]
        if count > 2 {
            for index in 2 ..< count {
                let extra = fixture.root.appendingPathComponent("extra-\(index).png")
                try FileManager.default.copyItem(at: fixture.file.url, to: extra)
                files.append(.init(id: UUID(), url: extra, name: extra.lastPathComponent))
            }
        }
        await feature.analyze(files)
        let pairCount = min(count * (count - 1) / 2, 2)
        #expect(feature.results.allSatisfy { $0.report?.incomplete == false })
        #expect(feature.selectionReport?.decision == .tie)
        #expect(feature.selectionReport?.pairReports.count == pairCount)
        #expect(feature.selectionReport?.pairReports.first?.decision == .tie)
        #expect(feature.manifest?.budget.attempts[.comparison] == pairCount + 1)
        let calls = await backend.responses
        await feature.resume()
        #expect(feature.selectionReport?.pairReports.count == pairCount)
        #expect(await backend.responses == calls)
        #expect(feature.manifest?.budget.attempts[.comparison] == pairCount + 1)
    }

    @Test @MainActor func `board records full frame transforms in stable image order`() throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = try #require(OrientationNormalizedImageLoader.loadCGImage(from: Data(contentsOf: fixture.file.url)))
        let (board, cells) = try CombinedReviewFeature.comparisonBoard([(.init(rawValue: "B"), image), (.init(rawValue: "A"), image)])
        #expect(board.width == 2048 && board.height == 2048)
        #expect(cells.map(\.imageID.rawValue) == ["A", "B"])
        #expect(cells.allSatisfy { abs($0.rect.width / $0.rect.height - 128.0 / 96.0) < 0.001 && $0.rect.minY >= 48 })
    }

    @Test func `selection budget preserves mandatory synthesis and fair crop limits`() throws {
        let images = (0 ..< 8).map { ReviewImageID(rawValue: String($0)) }
        let allocation = ReviewBudget.cropAllocation(images: images, counts: Dictionary(uniqueKeysWithValues: images.map { ($0, 3) }), depth: .standard)
        #expect(allocation.count == 16)
        #expect(images.allSatisfy { id in allocation.filter { $0 == id }.count == 2 })
        var budget = try ReviewBudget(depth: .standard, images: 8)
        for id in allocation {
            try budget.consume(.crop, imageID: id)
        }
        #expect(throws: ReviewRunError.self) { try budget.consume(.crop, imageID: images[0]) }
        for id in images {
            try budget.consume(.report, imageID: id)
        }
        try budget.consume(.comparison, imageID: nil)
        #expect(budget.attempts[.report] == 8 && budget.attempts[.comparison] == 1)
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

    @Test @MainActor func `preflight replaces incompatible RAW setting before creating a run`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        feature.sourcePreference = .rawDetail
        await feature.prepareParameters([fixture.file])
        #expect(feature.sourcePreference == .highQualityPreview)
        #expect(feature.sourceAvailability?.rawDisabledReason != nil)
        #expect(feature.parameterStatus.contains("RAW detail disabled"))
        #expect(feature.canStartReview)
        #expect(!feature.canStartReview(for: []))
        #expect(feature.manifest == nil)
        #expect(feature.failureMessage == nil)
        await feature.analyze([fixture.file])
        #expect(feature.manifest?.snapshot.sourcePreference == ReviewSourcePreference.highQualityPreview.rawValue)
        #expect(feature.result?.report != nil)
    }

    @Test @MainActor func `invalid criteria and selection are preparation status rather than review errors`() async throws {
        let fixture = try fixture(); defer { try? FileManager.default.removeItem(at: fixture.root) }
        let feature = makeFeature(fixture, backend: ReviewFakeBackend())
        await feature.prepareParameters([fixture.file])
        feature.criteria = " "
        #expect(!feature.canStartReview)
        #expect(feature.criteriaStatus != nil)
        await feature.analyze([fixture.file])
        #expect(feature.failureMessage == nil)
        #expect(feature.manifest == nil)
        feature.criteria = String(repeating: "ø", count: 257)
        #expect(feature.criteriaStatus != nil)
        await feature.prepareParameters([])
        #expect(feature.sourceAvailability == nil)
        #expect(!feature.canStartReview)
        #expect(feature.parameterStatus.contains("select 1–8"))
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
    let hasSAM: Bool, hasCLIP: Bool, comparisonTie: Bool, invalidCrop: Bool, invalidReport: Bool
    var delayCrop: Bool
    var cropContinuation: CheckedContinuation<Void, Never>?
    var cropStarted = false
    var responses = 0
    init(hasSAM: Bool = false, hasCLIP: Bool = false, comparisonTie: Bool = false, invalidCrop: Bool = false, invalidReport: Bool = false, delayCrop: Bool = false) {
        self.hasSAM = hasSAM; self.hasCLIP = hasCLIP; self.comparisonTie = comparisonTie; self.invalidCrop = invalidCrop; self.invalidReport = invalidReport; self.delayCrop = delayCrop
    }

    func stopDelay() {
        delayCrop = false
    }

    func models() -> [String: ReviewModelSnapshot] {
        var models = ["qwen": Self.qwen]
        if hasSAM {
            models["sam"] = .init(identity: "SAM", runtimeVersion: "test", preprocessing: "test", encoderWidth: 0, encoderHeight: 0, contextTokens: nil, imageTokens: nil)
        }
        if hasCLIP {
            models["clip"] = .init(identity: "CLIP", runtimeVersion: "test", preprocessing: "crop", encoderWidth: 224, encoderHeight: 224, contextTokens: nil, imageTokens: nil)
        }
        return models
    }

    func respond(instruction: String, image _: CGImage, tokens _: Int) async throws -> String {
        responses += 1
        if instruction.contains("Compare for goal:"), comparisonTie {
            var references: [(String, ReviewEvidenceReference)] = []
            for line in instruction.split(separator: "\n") {
                guard let first = line.split(separator: " ").first, UUID(uuidString: String(first)) != nil,
                      let start = line.firstIndex(of: "{"), let end = line[start...].firstIndex(of: "}"),
                      let ref = try? JSONDecoder().decode(ReviewEvidenceReference.self, from: Data(line[start ... end].utf8)),
                      !references.contains(where: { $0.0 == String(first) }) else { continue }
                references.append((String(first), ref))
            }
            let ids = references.map { ReviewImageID(rawValue: $0.0) }
            let report = ReviewSelectionReport(comparability: .comparable, decision: .tie, preferred: ids,
                                               claims: [.init(imageIDs: ids, claim: .init(text: "Both compositions retain the centered subject", type: "composition", evidence: references.map(\.1), uncertainty: "No supported aesthetic preference", contradictions: []))], reason: "Composition tie; identity is unverified")
            return try String(decoding: JSONEncoder().encode(report), as: UTF8.self)
        }
        if instruction.contains("Compare for goal:") {
            return "{\"comparability\":\"unrelated\",\"decision\":\"abstain\",\"preferred\":[],\"reason\":\"Different scenes; retain individual reviews\",\"claims\":[]}"
        }
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

    func clip(image _: CGImage, criteria _: String, model: ReviewModelSnapshot) throws -> CombinedReviewCLIPResult {
        guard hasCLIP else { throw ReviewRunError.modelUnavailable }
        return .init(relevance: 0.5, embedding: [1, 0], model: model)
    }
}

private nonisolated struct ReviewFakeScorer: SubjectMaskFocusScoring {
    func score(image _: CGImage, subjectMask _: CGImage, normalizedAFPoint _: CGPoint?) async throws -> SubjectMaskFocusEvidence? {
        .init(finalScore: 0.5, broadSubjectScore: 0.4, localDetailScore: 0.5, fineDetailScore: 0.6, maskCoverage: 0.25,
              autofocusInsideMask: nil, usableLocalPatch: true, backgroundDominancePenaltyApplied: false)
    }
}
