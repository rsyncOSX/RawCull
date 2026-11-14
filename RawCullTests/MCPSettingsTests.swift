import Foundation
@testable import RawCull
import Testing

@Suite("MCP Settings result visibility")
struct MCPSettingsTests {
    @Test func oneTimeResultIsVisibleWithoutGrantUntilCleared() throws {
        var job = completedJob()
        job.setupRequestId = UUID()
        job.catalogDisplayName = "One-time folder"
        let result = try #require(SharedResult(job: job, grant: nil))
        #expect(result.id == job.jobId)
        #expect(result.catalogName == "One-time folder")
        job.bursts = nil
        job.coverage = nil
        job.resultCleared = true
        #expect(SharedResult(job: job, grant: nil) == nil)
    }

    @Test func savedGrantResultRequiresCurrentMatchingAuthorization() {
        let job = completedJob()
        let matching = CatalogGrant(id: job.catalogId, displayName: "Saved folder", summary: nil, analysisEnabled: true)
        let disabled = CatalogGrant(id: job.catalogId, displayName: "Saved folder", summary: nil, analysisEnabled: false)
        let replacement = CatalogGrant(id: UUID(), displayName: "Replacement folder", summary: nil, analysisEnabled: true)
        #expect(SharedResult(job: job, grant: matching)?.catalogName == "Saved folder")
        #expect(SharedResult(job: job, grant: disabled) == nil)
        #expect(SharedResult(job: job, grant: replacement) == nil)
        #expect(SharedResult(job: job, grant: nil) == nil)
    }

    private func completedJob() -> AnalysisJob {
        var job = AnalysisJob(jobId: UUID(), catalogId: UUID(), createdAt: .now, updatedAt: .now)
        job.coverage = .init(photoCount: 0, burstCount: 0, singletonCount: 0, unevaluatedCount: 0,
                             skippedByReason: [:], similarityBackends: [:])
        job.bursts = []
        job.finish(.completed)
        return job
    }
}
