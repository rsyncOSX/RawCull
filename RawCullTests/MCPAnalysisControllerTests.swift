import Foundation
@testable import RawCull
import Testing

/// Transition tests for `MCPAnalysisController`, driven one `tick()` at a time
/// against temporary stores. See Docs/code-quality-followups-plan.md, Finding 3.
@Suite("MCP analysis controller", .serialized)
@MainActor
struct MCPAnalysisControllerTests {
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
}
