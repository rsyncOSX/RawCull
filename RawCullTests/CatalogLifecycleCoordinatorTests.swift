import Foundation
@testable import RawCull
import Testing

@MainActor
struct CatalogLifecycleCoordinatorTests {
    @Test(arguments: [false, true])
    func `Superseded persistence completion cannot act or clear the new transition`(oldFlushSucceeds: Bool) async throws {
        let coordinator = CatalogLifecycleCoordinator()
        let firstStarted = CatalogTestGate()
        let firstRelease = CatalogTestGate()
        let secondStarted = CatalogTestGate()
        let secondRelease = CatalogTestGate()
        var actions: [String] = []
        coordinator.startTransition(
            flushPersistence: {
                firstStarted.open()
                await firstRelease.wait()
                return oldFlushSucceeds
            },
            isStillSelected: { true },
            onFailure: { actions.append("old failure") },
            onReady: { actions.append("old ready") },
        )
        let first = try #require(coordinator.transitionTask)
        await firstStarted.wait()
        coordinator.startTransition(
            flushPersistence: {
                secondStarted.open()
                await secondRelease.wait()
                return true
            },
            isStillSelected: { true },
            onFailure: { actions.append("new failure") },
            onReady: { actions.append("new ready") },
        )
        let second = try #require(coordinator.transitionTask)
        await secondStarted.wait()
        firstRelease.open()
        await first.value
        #expect(actions.isEmpty)
        #expect(coordinator.transitionTask != nil)
        secondRelease.open()
        await second.value
        #expect(actions == ["new ready"])
        #expect(coordinator.transitionTask == nil)
    }

    @Test(arguments: [false, true])
    func `Persistence failure restores selection only while still selected`(stillSelected: Bool) async throws {
        let coordinator = CatalogLifecycleCoordinator()
        var restored = false
        var started = false
        coordinator.startTransition(
            flushPersistence: { false },
            isStillSelected: { stillSelected },
            onFailure: { restored = true },
            onReady: { started = true },
        )
        let task = try #require(coordinator.transitionTask)
        await task.value
        #expect(restored == stillSelected)
        #expect(!started)
        #expect(coordinator.transitionTask == nil)
    }

    @Test
    func `Cancelled load retains access until its worker returns`() async throws {
        let coordinator = CatalogLifecycleCoordinator()
        let url = URL(filePath: "/tmp/lifecycle-worker-" + UUID().uuidString)
        let started = CatalogTestGate()
        let release = CatalogTestGate()
        var stops: [URL] = []
        coordinator.startSecurityScopedResource = { _ in true }
        coordinator.stopSecurityScopedResource = { stops.append($0) }
        #expect(coordinator.startSecurityScopedAccess(for: url))
        coordinator.startLoad(for: url) {
            started.open()
            await release.wait()
            #expect(Task.isCancelled)
        }
        let task = try #require(coordinator.loadTask)
        await started.wait()
        coordinator.cancelLoad()
        #expect(coordinator.activeLoadURL == nil)
        #expect(coordinator.loadTask == nil)
        #expect(!coordinator.hasActiveSecurityScopedAccess(for: url))
        #expect(stops.isEmpty)
        release.open()
        await task.value
        #expect(stops == [url.standardizedFileURL])
    }

    @Test
    func `Coordinator destruction releases its active grant`() {
        let url = URL(filePath: "/tmp/lifecycle-" + UUID().uuidString)
        var stops: [URL] = []
        var coordinator: CatalogLifecycleCoordinator? = CatalogLifecycleCoordinator()
        coordinator?.startSecurityScopedResource = { _ in true }
        coordinator?.stopSecurityScopedResource = { stops.append($0) }
        #expect(coordinator?.startSecurityScopedAccess(for: url) == true)
        coordinator = nil
        #expect(stops == [url.standardizedFileURL])
    }
}
