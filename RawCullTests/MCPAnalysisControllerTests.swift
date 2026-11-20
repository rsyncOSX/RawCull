import AppKit
import Foundation
@testable import RawCull
import RawCullCore
import Testing

/// Characterization tests for `MCPAnalysisController` transitions, driven one
/// `tick()` at a time against temporary stores. They pin today's behaviour
/// before the controller's state becomes explicit
/// (Docs/code-quality-followups-plan.md, Finding 3, step 3.2).
@Suite("MCP analysis controller", .serialized)
@MainActor
struct MCPAnalysisControllerTests {
    // MARK: Idle

    @Test func `idle tick with an empty store changes nothing`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })

        await controller.tick()

        #expect(try fixture.jobs.read() == nil)
        #expect(try fixture.setupStore.pending() == nil)
        #expect(workspace.catalogLoads.isEmpty)
        #expect(workspace.burstAnalysisRuns == 0)
    }

    // MARK: Catalog setup

    @Test func `setup request while idle shows a sheet that expires at its deadline`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        let request = try fixture.submitSetup(hint: "Unknown folder")

        await controller.tick()
        #expect(try await fixture.settle { fixture.presentedSheets.count == 1 })
        #expect(fixture.finishedSheets == 0)

        fixture.now = request.expiresAt
        await controller.tick()
        #expect(try await fixture.settle { fixture.finishedSheets == 1 })
        // Cancellation by expiry writes no response; the stored request is untouched.
        #expect(try fixture.setupStore.request(request.requestId)?.state == .pendingApproval)
    }

    @Test func `quit pending suspends setup and cancelling the quit shows it again`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        let request = try fixture.submitSetup(hint: "Unknown folder")

        await controller.tick()
        #expect(try await fixture.settle { fixture.presentedSheets.count == 1 })

        controller.setTerminationPending(true)
        #expect(try await fixture.settle { fixture.finishedSheets == 1 })
        await controller.tick()
        try await Task.sleep(for: .milliseconds(100))
        #expect(fixture.presentedSheets.count == 1)

        controller.setTerminationPending(false)
        await controller.tick()
        #expect(try await fixture.settle { fixture.presentedSheets.count == 2 })
        #expect(try fixture.setupStore.request(request.requestId)?.state == .pendingApproval)
    }

    @Test func `denied setup records the denial`() async throws {
        let fixture = try MCPControllerFixture()
        let catalog = try fixture.makeCatalog()
        let workspace = FakeMCPWorkspace()
        workspace.sources = [catalog.source]
        fixture.answerSheet = { _ in .alertThirdButtonReturn }
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        let request = try fixture.submitSetup()

        await controller.tick()
        #expect(try await fixture.settle { try fixture.setupStore.request(request.requestId)?.state == .denied })
        #expect(try fixture.jobs.read() == nil)
    }

    // MARK: Analysis

    /// Approves a setup request for `catalog` and returns the queued job.
    private func approveSetup(
        _ fixture: MCPControllerFixture, controller: MCPAnalysisController,
        workspace: FakeMCPWorkspace, catalog: (source: ARWSourceCatalog, files: [FileItem]),
    ) async throws -> AnalysisJob {
        workspace.sources = [catalog.source]
        workspace.onCatalogLoad = { workspace, source, url in
            workspace.loadedSource = source
            workspace.files = catalog.files
            if let url { workspace.accessibleURLs.insert(url.standardizedFileURL) }
        }
        fixture.answerSheet = { _ in .alertFirstButtonReturn }
        let request = try fixture.submitSetup()
        await controller.tick()
        #expect(try await fixture.settle { try fixture.jobs.read()?.state == .queued })
        let job = try #require(try fixture.jobs.read())
        #expect(job.setupRequestId == request.requestId)
        #expect(try fixture.setupStore.request(request.requestId)?.state == .queued)
        #expect(try await fixture.settle { try fixture.setupStore.pending() == nil })
        return job
    }

    @Test func `approved setup job is claimed, runs and completes`() async throws {
        let fixture = try MCPControllerFixture()
        let catalog = try fixture.makeCatalog()
        let workspace = FakeMCPWorkspace()
        let controller = fixture.makeController()
        var prepared = 0
        controller.attach(viewModel: workspace, prepare: { prepared += 1 }, canStart: { true })
        let queued = try await approveSetup(fixture, controller: controller, workspace: workspace, catalog: catalog)

        await controller.tick()
        #expect(try await fixture.settle { try fixture.jobs.read()?.state == .completed })
        let job = try #require(try fixture.jobs.read())
        #expect(job.jobId == queued.jobId)
        #expect(job.filesScanned == 1)
        #expect(job.coverage?.photoCount == 1)
        #expect(job.bursts?.isEmpty == true)
        #expect(prepared == 1)
        #expect(workspace.catalogLoads == [catalog.source])
        #expect(workspace.burstAnalysisRuns == 1)
        #expect(workspace.presentedBurstResults == 1)
    }

    @Test func `analysis that returns no result fails the job`() async throws {
        let fixture = try MCPControllerFixture()
        let catalog = try fixture.makeCatalog()
        let workspace = FakeMCPWorkspace()
        workspace.analyze = { _ in nil }
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        _ = try await approveSetup(fixture, controller: controller, workspace: workspace, catalog: catalog)

        await controller.tick()
        #expect(try await fixture.settle { try fixture.jobs.read()?.state == .failed })
        #expect(try fixture.jobs.read()?.message == "The catalog or analysis settings changed during the job.")
    }

    @Test func `cancellation requested by the helper cancels a running job`() async throws {
        let fixture = try MCPControllerFixture()
        let catalog = try fixture.makeCatalog()
        let workspace = FakeMCPWorkspace()
        let jobs = fixture.jobs
        workspace.analyze = { _ in
            _ = try? jobs.update { current in
                guard var current else { return nil }
                current.cancellationRequested = true
                return current
            }
            return BurstAnalysisPipelineResult(
                groups: [], rankings: [], restoredReviewStates: [:], cacheOutcome: .miss, diagnostics: [],
            )
        }
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        _ = try await approveSetup(fixture, controller: controller, workspace: workspace, catalog: catalog)

        await controller.tick()
        #expect(try await fixture.settle { try fixture.jobs.read()?.state == .cancelled })
        #expect(workspace.presentedBurstResults == 0)
    }

    @Test func `quitting during analysis cancels the job and publishes nothing after quit`() async throws {
        let fixture = try MCPControllerFixture()
        let catalog = try fixture.makeCatalog()
        let workspace = FakeMCPWorkspace()
        var analysisStarted = false
        workspace.analyze = { _ in
            analysisStarted = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return BurstAnalysisPipelineResult(
                groups: [], rankings: [], restoredReviewStates: [:], cacheOutcome: .miss, diagnostics: [],
            )
        }
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, prepare: {}, canStart: { true })
        _ = try await approveSetup(fixture, controller: controller, workspace: workspace, catalog: catalog)
        await controller.tick()
        #expect(try await fixture.settle { analysisStarted })

        await controller.stopForQuit()

        let job = try #require(try fixture.jobs.read())
        #expect(job.state == .cancelled)
        #expect(job.message == "RawCull quit.")
        try await Task.sleep(for: .milliseconds(200))
        #expect(try fixture.jobs.read()?.state == .cancelled)
        #expect(try fixture.jobs.read()?.message == "RawCull quit.")
    }

    // MARK: Photo-assessment follow-ups

    private let identity = QwenInferenceRuntime.Identity(name: "Fake Qwen", generation: 1)

    /// A follow-up whose preparation never finishes, so it stays running until stopped.
    private func startHangingFollowUp(
        _ fixture: MCPControllerFixture, workspace: FakeMCPWorkspace,
    ) async throws -> (MCPAnalysisController, AnalysisJobStore.FollowUpRequest, () -> Bool) {
        let controller = fixture.makeController()
        var preparing = false
        controller.attach(
            viewModel: workspace, qwen: FakeMCPPhotoAssessor(identity: nil), prepare: {},
            preparePhotoAssessment: {
                preparing = true
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                }
            },
            canStart: { true },
        )
        let request = try fixture.queueFollowUp()
        await controller.tick()
        #expect(try await fixture.settle { preparing })
        #expect(try fixture.jobs.followUpStatus(request.id).state == .running)
        return (controller, request, { preparing })
    }

    @Test func `follow up is refused as busy while the workspace is loading`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        workspace.isMCPWorkspaceLoading = true
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, qwen: FakeMCPPhotoAssessor(identity: identity), prepare: {},
                          canStart: { true })
        let request = try fixture.queueFollowUp()

        await controller.tick()

        let status = try fixture.jobs.followUpStatus(request.id)
        #expect(status.errorCode == MCPAssessmentStopReason.busy.rawValue)
        #expect(status.state != .running)
    }

    @Test func `follow up times out after 180 seconds`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let (controller, request, _) = try await startHangingFollowUp(fixture, workspace: workspace)

        fixture.instant = fixture.instant.advanced(by: .seconds(179))
        await controller.tick()
        #expect(try fixture.jobs.followUpStatus(request.id).state == .running)

        fixture.instant = fixture.instant.advanced(by: .seconds(1))
        await controller.tick()
        #expect(try await fixture.settle { try fixture.jobs.followUpStatus(request.id).state != .running })
        #expect(try fixture.jobs.followUpStatus(request.id).errorCode == MCPAssessmentStopReason.executionTimeout.rawValue)
    }

    @Test func `lease invalidation stops a follow up as modelChanged`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let (_, request, _) = try await startHangingFollowUp(fixture, workspace: workspace)

        CombinedReviewLease.shared.invalidate()

        #expect(try await fixture.settle { try fixture.jobs.followUpStatus(request.id).state != .running })
        #expect(try fixture.jobs.followUpStatus(request.id).errorCode == MCPAssessmentStopReason.modelChanged.rawValue)
    }

    @Test func `cancellation requested by the helper stops a follow up`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let (controller, request, _) = try await startHangingFollowUp(fixture, workspace: workspace)

        try fixture.jobs.cancelFollowUp(request.id)
        await controller.tick()

        #expect(try await fixture.settle { try fixture.jobs.followUpStatus(request.id).state != .running })
        let status = try fixture.jobs.followUpStatus(request.id)
        #expect(status.state == .cancelled)
        #expect(status.errorCode == nil)
    }

    @Test func `missing model fails a follow up as modelUnavailable`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let controller = fixture.makeController()
        controller.attach(viewModel: workspace, qwen: FakeMCPPhotoAssessor(identity: nil), prepare: {},
                          canStart: { true })
        let request = try fixture.queueFollowUp()

        await controller.tick()

        #expect(try await fixture.settle { try fixture.jobs.followUpStatus(request.id).state != .running })
        #expect(try fixture.jobs.followUpStatus(request.id).errorCode == MCPAssessmentStopReason.modelUnavailable.rawValue)
    }

    @Test func `quitting during a follow up waits for it and stops it`() async throws {
        let fixture = try MCPControllerFixture()
        let workspace = FakeMCPWorkspace()
        let (controller, request, _) = try await startHangingFollowUp(fixture, workspace: workspace)

        await controller.stopForQuit()

        // stopForQuit awaits the follow-up task, so its terminal state is already written.
        #expect(try fixture.jobs.followUpStatus(request.id).state != .running)
    }
}

@Suite("MCP assessment stop reasons")
@MainActor
struct MCPAssessmentStopReasonTests {
    private struct OtherError: Error {}

    @Test func `a recorded reason wins over the error`() {
        #expect(MCPAnalysisController.stopReason(for: CancellationError(), recorded: .executionTimeout) == .executionTimeout)
        #expect(MCPAnalysisController.stopReason(for: OtherError(), recorded: .modelChanged) == .modelChanged)
    }

    @Test func `errors map to their published codes`() {
        #expect(MCPAnalysisController.stopReason(for: CancellationError(), recorded: nil) == nil)
        #expect(MCPAnalysisController.stopReason(
            for: QwenInferenceRuntime.MCPAssessmentError.modelChanged, recorded: nil,
        ) == .modelChanged)
        #expect(MCPAnalysisController.stopReason(for: QwenModelError.modelUnavailable, recorded: nil) == .modelUnavailable)
        #expect(MCPAnalysisController.stopReason(
            for: MCPAnalysisController.FollowUpCatalogError.reauthorizationRequired, recorded: nil,
        ) == .reauthorizationRequired)
        #expect(MCPAnalysisController.stopReason(for: OtherError(), recorded: nil) == .assessmentFailed)
    }

    @Test func `raw values are the wire contract`() {
        #expect(MCPAssessmentStopReason.allCases.map(\.rawValue) == [
            "busy", "executionTimeout", "modelChanged", "modelUnavailable",
            "reauthorizationRequired", "assessmentFailed", "allPhotosFailed",
        ])
    }
}
