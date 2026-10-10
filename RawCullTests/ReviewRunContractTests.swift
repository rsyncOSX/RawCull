import Foundation
@testable import RawCull
import Testing

@Suite("Combined Review run contract", .tags(.smoke))
struct ReviewRunContractTests {
    @Test func `budgets reserve coverage and count every attempt`() throws {
        let images = (0 ..< 8).map { ReviewImageID(rawValue: String($0)) }
        var budget = try ReviewBudget(depth: .deep, images: 8)
        #expect(budget.maximumQwenAttempts == 67)
        for image in images {
            for _ in 0 ..< 4 {
                try budget.consume(.crop, imageID: image)
            }
        }
        #expect(throws: ReviewRunError.self) { try budget.consume(.crop, imageID: images[0]) }
        for image in images {
            try budget.consume(.overview, imageID: image); try budget.consume(.report, imageID: image)
        }
        #expect(throws: ReviewRunError.self) { try budget.consume(.overview, imageID: images[0]) }
        try budget.recordChange(.init(category: .overview, imageID: nil, newLimit: 9, reason: "Explicit retry plan"))
        try budget.recordChange(.init(category: .overview, imageID: images[0], newLimit: 2, reason: "Explicit retry plan"))
        try budget.consume(.overview, imageID: images[0])
        #expect(budget.attempts[.overview] == 9)
        #expect(budget.maximumQwenAttempts == 68)
        let allocation = ReviewBudget.cropAllocation(images: images, counts: Dictionary(uniqueKeysWithValues: images.map { ($0, 8) }), depth: .deep)
        #expect(Array(allocation.prefix(8)) == images)
        #expect(allocation.count == 32)
    }

    @Test func `compatibility changes only consuming stages`() throws {
        let original = snapshot()
        let changed = snapshot(criteria: "Composition")
        let image = original.files[0]
        #expect(try ReviewCompatibility.make(snapshot: original, image: image, stage: .measurement) == ReviewCompatibility.make(snapshot: changed, image: image, stage: .measurement))
        #expect(try ReviewCompatibility.make(snapshot: original, image: image, stage: .report) != ReviewCompatibility.make(snapshot: changed, image: image, stage: .report))
        let newModel = snapshot(model: "replacement")
        #expect(try ReviewCompatibility.make(snapshot: original, image: image, stage: .overview) != ReviewCompatibility.make(snapshot: newModel, image: image, stage: .overview))
        #expect(try ReviewCompatibility.make(snapshot: original, image: image, stage: .source, sourceRender: "a") != ReviewCompatibility.make(snapshot: original, image: image, stage: .source, sourceRender: "b"))
    }

    @Test func `cancellation preserves independent observations and spent budget`() throws {
        var run = try manifest()
        try run.begin(id("source")); try run.finish(id("source"), state: .completed, artifactKey: "source")
        try run.begin(id("crop"), category: .crop); try run.finish(id("crop"), state: .completed, artifactKey: "crop")
        try run.begin(id("measurement")); run.cancel()
        let expected = Dictionary(uniqueKeysWithValues: run.work.map { ($0.id, $0.compatibility) })
        run.restore(expected: expected, validArtifacts: ["source", "crop"])
        #expect(run.work.first { $0.id == id("crop") }?.state == .completed)
        #expect(run.work.first { $0.id == id("measurement") }?.state == .pending)
        #expect(run.budget.attempts[.crop] == 1)
        #expect(try !run.ready(#require(run.work.first { $0.stage == .reconciliation })))
        try run.begin(id("measurement")); try run.finish(id("measurement"), state: .skipped, reason: "Unavailable measurement")
        #expect(try run.ready(#require(run.work.first { $0.stage == .reconciliation })))
    }

    @Test func `invalidation propagates through completed descendants`() throws {
        var run = try manifest()
        for name in ["source", "measurement", "crop", "reconcile", "report"] {
            let category: ReviewAttemptCategory? = name == "crop" ? .crop : name == "report" ? .report : name == "reconcile" ? .reconciliation : nil
            try run.begin(id(name), category: category); try run.finish(id(name), state: .completed, artifactKey: name)
        }
        var expected = Dictionary(uniqueKeysWithValues: run.work.map { ($0.id, $0.compatibility) })
        expected[id("measurement")] = .init(fields: ["render": "changed"])
        run.restore(expected: expected, validArtifacts: ["source", "measurement", "crop", "reconcile", "report"])
        #expect(run.work.first { $0.id == id("crop") }?.state == .completed)
        #expect(run.work.first { $0.id == id("report") }?.state == .pending)
        #expect(run.work.first { $0.id == id("reconcile") }?.state == .pending)
    }

    @Test func `manifests require every accepted image and acyclic dependencies`() throws {
        var run = try manifest()
        run.work.removeAll { $0.stage == .report }
        #expect(throws: ReviewRunError.self) { try run.validate() }
        run = try manifest()
        let source = try #require(run.work.first)
        run.work[0] = ReviewWorkItem(id: source.id, imageID: source.imageID, stage: .source,
                                     dependencies: [.init(id: id("report"), allowsUnavailable: false)], compatibility: source.compatibility)
        #expect(throws: ReviewRunError.self) { try run.validate() }
        let excessive = snapshot(count: 9)
        #expect(throws: ReviewRunError.self) { try excessive.validate() }
    }

    @Test func `atomic artifacts restore partial work and reject future schemas`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewArtifactStore(root: root)
        var run = try manifest()
        try run.begin(id("source"))
        let item = try #require(run.work.first)
        let key = store.artifactKey(item.id, compatibility: item.compatibility)
        try run.finish(item.id, state: .completed, artifactKey: key)
        let artifact = ReviewStageArtifact(workID: item.id, compatibility: item.compatibility, payload: Data("complete".utf8), created: Date())
        try await store.commit(artifact, manifest: run)
        let history = try await store.historyManifests()
        #expect(history.count == 1)
        #expect(history.first?.snapshot.id == run.snapshot.id)
        #expect(history.first?.work.first?.state == .completed)
        var restored = try await store.loadManifest(run.snapshot.id)
        #expect(await store.validArtifactKeys(for: restored) == [key])
        restored.restore(expected: Dictionary(uniqueKeysWithValues: restored.work.map { ($0.id, $0.compatibility) }), validArtifacts: [])
        #expect(restored.work[0].state == .pending)
        let cancelledWrite = Task { [run] in
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.commit(artifact, manifest: run)
        }
        await #expect(throws: CancellationError.self) { try await cancelledWrite.value }
        #expect(try await store.loadArtifact(key: key, expected: item.compatibility).payload == artifact.payload)
        let url = root.appendingPathComponent("runs/\(run.snapshot.id.uuidString).json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        object["schemaVersion"] = 99
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: url)
        await #expect(throws: ReviewRunError.self) { try await store.loadManifest(run.snapshot.id) }
        await #expect(throws: ReviewRunError.self) { try await store.saveManifest(run) }
        #expect(try Data(contentsOf: url) == future)
    }

    @Test func `derived cache eviction preserves evidence and rejects traversal`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewArtifactStore(root: root, maximumInputBytes: 10)
        let first = try await store.retainInput(Data(repeating: 1, count: 6))
        let second = try await store.retainInput(Data(repeating: 2, count: 6))
        #expect(try await store.input(second) == Data(repeating: 2, count: 6))
        await #expect(throws: (any Error).self) { try await store.input(first) }
        await #expect(throws: ReviewRunError.self) { try await store.input("../private") }
        await #expect(throws: ReviewRunError.self) { try await store.retainInput(Data(repeating: 3, count: 11)) }
    }

    @Test func `evidence claims cannot invent IDs`() throws {
        let ref = ReviewEvidenceReference(kind: .region, id: "known")
        let claim = ReviewClaim(text: "Visible detail", type: "observation", evidence: [ref], uncertainty: "limited", contradictions: [])
        try claim.validate(allowed: [ref])
        #expect(throws: ReviewRunError.self) { try claim.validate(allowed: []) }
    }

    private func id(_ name: String) -> ReviewWorkID {
        .init(rawValue: name)
    }

    @Test func `resume rebuilds compatibility instead of trusting saved fields`() throws {
        var run = try manifest()
        let expected = try run.expectedCompatibility()
        run.work[0].compatibility = .init(fields: ["pipeline": "tampered", "model": "stale"])
        let rebuilt = try run.expectedCompatibility()
        #expect(rebuilt == expected)
        run.restore(expected: rebuilt, validArtifacts: [])
        #expect(run.work[0].compatibility == expected[run.work[0].id])
    }

    @Test func `latest run ignores filesystem modification dates and breaks creation ties`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ReviewArtifactStore(root: root)
        let first = try manifest()
        let data = try JSONEncoder().encode(first)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var snap = try #require(object["snapshot"] as? [String: Any])
        let otherID = UUID()
        snap["id"] = otherID.uuidString
        object["snapshot"] = snap
        let second = try JSONDecoder().decode(CombinedReviewRunV1.self, from: JSONSerialization.data(withJSONObject: object))
        try await store.saveManifest(first)
        try await store.saveManifest(second)
        let expectedID = max(first.snapshot.id.uuidString, second.snapshot.id.uuidString)
        let olderID = min(first.snapshot.id.uuidString, second.snapshot.id.uuidString)
        try FileManager.default.setAttributes([.modificationDate: Date.distantFuture],
            ofItemAtPath: root.appendingPathComponent("runs/\(olderID).json").path)
        #expect(try await store.latestManifest()?.snapshot.id.uuidString == expectedID)
    }

    @Test func `word boundaries permit ordinary observations and uncertainty limitations`() throws {
        let response = #"""
        {"regionID":"r","observations":"An eyelet and an iris-shaped pattern are visible.","uncertainty":"Eye detail and RAW recovery cannot be assessed.","insufficientEvidence":false}
        """#
        // Anatomical terms in claim text are still rejected.
        #expect(throws: ReviewRunError.self) { try CombinedReviewResponse.inspection(response, regionID: "r") }
        let safe = response.replacingOccurrences(of: "iris-shaped", with: "circular")
        #expect(try CombinedReviewResponse.inspection(safe, regionID: "r").observations.contains("eyelet"))
        let unsafe = safe.replacingOccurrences(of: "eyelet", with: "eye")
        #expect(throws: ReviewRunError.self) { try CombinedReviewResponse.inspection(unsafe, regionID: "r") }
    }

    private func snapshot(criteria: String = "Detail", model: String = "model", count: Int = 1) -> ReviewRunSnapshot {
        ReviewRunSnapshot(id: UUID(), files: (0 ..< count).map { .init(id: .init(rawValue: String($0)), fileID: UUID(), url: URL(filePath: "/fixture/\($0)"), displayName: "Fixture", fingerprint: String($0)) },
                          criteria: criteria, depth: .standard, sourcePreference: "highQualityPreview", retentionPolicy: .exactInputs, renderVersion: "render-v1",
                          models: ["qwen": .init(identity: model, runtimeVersion: "runtime", preprocessing: "stretch", encoderWidth: 448, encoderHeight: 448, contextTokens: 4096, imageTokens: 196)],
                          stageVersions: Dictionary(uniqueKeysWithValues: ReviewStage.allCases.map { ($0, "v1") }), responseTokens: 512,
                          pipelineVersion: "v1", created: Date(), expandedSelectionPlan: nil)
    }

    private func manifest() throws -> CombinedReviewRunV1 {
        let snap = snapshot()
        let image = snap.files[0].id
        let compatibility = ReviewCompatibility(fields: ["fixture": "v1"])
        func item(_ name: String, _ stage: ReviewStage, _ parents: [String], terminal: Bool = false) -> ReviewWorkItem {
            .init(id: id(name), imageID: image, stage: stage, dependencies: parents.map { .init(id: id($0), allowsUnavailable: terminal) }, compatibility: compatibility)
        }
        return try CombinedReviewRunV1(snapshot: snap, work: [item("source", .source, []), item("measurement", .measurement, ["source"]),
                                                              item("crop", .cropObservation, ["source"]), item("reconcile", .reconciliation, ["measurement", "crop"], terminal: true),
                                                              item("report", .report, ["reconcile"], terminal: true)], budget: ReviewBudget(depth: .standard, images: 1))
    }
}
