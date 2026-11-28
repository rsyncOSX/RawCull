import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
@Suite("Burst batch AI assessment")
struct BurstBatchAssessmentTests {
    private let catalog = URL(fileURLWithPath: "/tmp/BurstBatchCatalog")

    private func file(_ name: String) -> FileItem {
        FileItem(id: UUID(), url: catalog.appendingPathComponent(name), name: name, size: 1,
                 dateModified: .distantPast, exifData: nil, afFocusNormalized: nil)
    }

    private func result(
        group: Int, files: [FileItem], recommended: UUID?, second: UUID?,
        confidence: BurstDecisionConfidence = .medium,
    ) -> BurstAnalysisResult {
        BurstAnalysisResult(groupID: group, fileIDs: files.map(\.id), candidates: [], recommendedFileID: recommended,
                            secondBestFileID: second, confidence: confidence, reviewState: .algorithmReviewed,
                            isSafeForOneClickCulling: true, reasons: [], cautions: [])
    }

    @Test func `plan keeps ranked multi-frame bursts and their top two frames`() {
        let burst = [file("a.ARW"), file("b.ARW"), file("c.ARW")]
        let single = [file("d.ARW")]
        let unranked = [file("e.ARW"), file("f.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 3,
            groups: [BurstGroup(id: 2, fileIDs: burst.map(\.id)), BurstGroup(id: 5, fileIDs: single.map(\.id)),
                     BurstGroup(id: 7, fileIDs: unranked.map(\.id))],
            results: [2: result(group: 2, files: burst, recommended: burst[1].id, second: burst[0].id),
                      5: result(group: 5, files: single, recommended: single[0].id, second: nil),
                      7: result(group: 7, files: unranked, recommended: nil, second: nil)],
            files: burst + single + unranked,
        )
        #expect(plan.items.map(\.groupID) == [2])
        #expect(plan.items[0].targets == [burst[1].id.uuidString, burst[0].id.uuidString])
        #expect(plan.items[0].frames.map(\.photo.relativePath) == ["a.ARW", "b.ARW", "c.ARW"])
    }

    @Test func `closest calls keep unsure bursts with two picks, low confidence first`() {
        let high = [file("h1.ARW"), file("h2.ARW")]
        let medium = [file("m1.ARW"), file("m2.ARW")]
        let low = [file("l1.ARW"), file("l2.ARW")]
        let samePick = [file("s1.ARW"), file("s2.ARW")]
        let lowLater = [file("x1.ARW"), file("x2.ARW")]
        let groups = [high, medium, low, samePick, lowLater].enumerated().map {
            BurstGroup(id: $0.offset + 1, fileIDs: $0.element.map(\.id))
        }
        let results: [Int: BurstAnalysisResult] = [
            1: result(group: 1, files: high, recommended: high[0].id, second: high[1].id, confidence: .high),
            2: result(group: 2, files: medium, recommended: medium[0].id, second: medium[1].id, confidence: .medium),
            3: result(group: 3, files: low, recommended: low[0].id, second: low[1].id, confidence: .low),
            4: result(group: 4, files: samePick, recommended: samePick[0].id, second: samePick[0].id, confidence: .low),
            5: result(group: 5, files: lowLater, recommended: lowLater[1].id, second: lowLater[0].id, confidence: .low),
        ]
        let files = high + medium + low + samePick + lowLater
        let closest = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1, groups: groups, results: results, files: files,
            scope: .closestCalls,
        )
        #expect(closest.scope == .closestCalls)
        #expect(closest.items.map(\.groupID) == [3, 5, 2])
        #expect(closest.items.allSatisfy { $0.targets.count == 2 })
        #expect(BurstBatchAssessment.closestCallCount(groups: groups, results: results) == 3)

        let all = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1, groups: groups, results: results, files: files,
        )
        #expect(all.items.map(\.groupID) == [1, 2, 3, 4, 5])
    }

    @Test func `closest calls with none to assess explain why`() {
        let batch = BurstBatchAssessment(qwen: FakeMCPPhotoAssessor(identity: .init(name: "fake", generation: 1)),
                                         prepareModel: {}, lease: CombinedReviewLease())
        let files = [file("a.ARW"), file("b.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            results: [1: result(group: 1, files: files, recommended: files[0].id, second: files[1].id, confidence: .high)],
            files: files, scope: .closestCalls,
        )
        batch.start(plan, navigation: AIAssessmentNavigation()) { true }
        #expect(batch.phase == .failed("No close calls to assess: every burst has a clear pick."))
    }

    @Test func `run reports progress, finishes and releases the lease`() async throws {
        let lease = CombinedReviewLease()
        let identity = QwenInferenceRuntime.Identity(name: "fake", generation: 1)
        let batch = BurstBatchAssessment(qwen: FakeMCPPhotoAssessor(identity: identity), prepareModel: {}, lease: lease)
        let files = [file("missing1.ARW"), file("missing2.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            results: [1: result(group: 1, files: files, recommended: files[0].id, second: files[1].id)],
            files: files,
        )
        let navigation = AIAssessmentNavigation()
        batch.start(plan, navigation: navigation) { true }
        #expect(batch.isRunning)
        #expect(lease.isHeld)
        while batch.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(batch.phase == .finished)
        #expect(batch.completedBursts == 1)
        #expect(batch.fractionCompleted == 1)
        // The files don't exist, so both photos fail and no entry is published.
        #expect(batch.failedPhotos == 2)
        #expect(navigation.sessionEntries.isEmpty)
        try await Task.sleep(for: .milliseconds(10))
        #expect(!lease.isHeld)
    }

    @Test func `start is refused while another AI task holds the lease`() throws {
        let lease = CombinedReviewLease()
        try lease.acquire(UUID())
        let batch = BurstBatchAssessment(qwen: FakeMCPPhotoAssessor(identity: .init(name: "fake", generation: 1)),
                                         prepareModel: {}, lease: lease)
        #expect(batch.isBlockedByOtherAIWork)
        let files = [file("a.ARW"), file("b.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            results: [1: result(group: 1, files: files, recommended: files[0].id, second: files[1].id)],
            files: files,
        )
        batch.start(plan, navigation: AIAssessmentNavigation()) { true }
        #expect(!batch.isRunning)
        if case .failed = batch.phase {} else {
            Issue.record("Expected a failed phase")
        }
    }

    /// A model refresh stops whoever holds the AI lease. The batch refreshes the
    /// models for itself, so that refresh must not stop the batch.
    @Test func `refreshing the models does not cancel the batch that asked for it`() async throws {
        let lease = CombinedReviewLease()
        let qwen = LazyMCPPhotoAssessor()
        let batch = BurstBatchAssessment(qwen: qwen, prepareModel: {
            do {
                try await lease.invalidateAndWait()
                await qwen.load()
            } catch {}
        }, lease: lease)
        let files = [file("missing1.ARW"), file("missing2.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            results: [1: result(group: 1, files: files, recommended: files[0].id, second: files[1].id)],
            files: files,
        )
        batch.start(plan, navigation: AIAssessmentNavigation()) { true }
        while batch.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(batch.phase == .finished)
        #expect(batch.completedBursts == 1)
    }

    @Test func `another refresh still stops a batch that is preparing`() async throws {
        let lease = CombinedReviewLease()
        let batch = BurstBatchAssessment(qwen: LazyMCPPhotoAssessor(), prepareModel: {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
        }, lease: lease)
        let files = [file("a.ARW"), file("b.ARW")]
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: [BurstGroup(id: 1, fileIDs: files.map(\.id))],
            results: [1: result(group: 1, files: files, recommended: files[0].id, second: files[1].id)],
            files: files,
        )
        batch.start(plan, navigation: AIAssessmentNavigation()) { true }
        try await Task.sleep(for: .milliseconds(30))
        try await lease.invalidateAndWait()
        #expect(!batch.isRunning)
        #expect(!lease.isHeld)
    }

    @Test func `cancel stops the run`() async throws {
        let lease = CombinedReviewLease()
        let batch = BurstBatchAssessment(qwen: FakeMCPPhotoAssessor(identity: .init(name: "fake", generation: 1)),
                                         prepareModel: {}, lease: lease)
        let groups = (1 ... 3).map { id in (id, [file("\(id)a.ARW"), file("\(id)b.ARW")]) }
        let plan = BurstBatchAssessment.makePlan(
            catalog: catalog, catalogName: "Test", generation: 1,
            groups: groups.map { BurstGroup(id: $0.0, fileIDs: $0.1.map(\.id)) },
            results: Dictionary(uniqueKeysWithValues: groups.map {
                ($0.0, result(group: $0.0, files: $0.1, recommended: $0.1[0].id, second: $0.1[1].id))
            }),
            files: groups.flatMap(\.1),
        )
        batch.start(plan, navigation: AIAssessmentNavigation()) { true }
        batch.cancel()
        #expect(batch.phase == .cancelling)
        while batch.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(batch.phase == .cancelled)
        #expect(batch.completedBursts < 3)
    }
}
