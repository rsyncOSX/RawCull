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

    private func result(group: Int, files: [FileItem], recommended: UUID?, second: UUID?) -> BurstAnalysisResult {
        BurstAnalysisResult(groupID: group, fileIDs: files.map(\.id), candidates: [], recommendedFileID: recommended,
                            secondBestFileID: second, confidence: .medium, reviewState: .algorithmReviewed,
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
