//
//  ThumbnailLoaderConcurrencyTests.swift
//  RawCullVerifyTests
//
//

@testable import RawCull
import Testing

struct ThumbnailLoaderConcurrencyTests {
    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    func `saturated loader queues waiter until slot is released`() async throws {
        let loader = ThumbnailLoader()
        try await saturate(loader)

        let waiter = Task {
            await loader.acquireSlotForTesting()
        }

        try await waitForSlotSnapshot(loader) { snapshot in
            snapshot.activeTasks == snapshot.maxConcurrent && snapshot.pendingContinuations == 1
        }

        await loader.releaseSlotForTesting()
        let granted = await waiter.value
        #expect(granted)

        var snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.pendingContinuations == 0)

        await loader.releaseSlotForTesting()
        snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent - 1)

        await releaseAllActiveSlots(loader)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    func `cancelled queued waiter does not consume slot`() async throws {
        let loader = ThumbnailLoader()
        try await saturate(loader)

        let waiter = Task {
            await loader.acquireSlotForTesting()
        }

        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 1 }
        waiter.cancel()

        let granted = await waiter.value
        #expect(!granted)

        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 0 }
        let snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.maxObservedActiveTasks == snapshot.maxConcurrent)

        await releaseAllActiveSlots(loader)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    func `max concurrency bound holds while queued waiters cancel and resume`() async throws {
        let loader = ThumbnailLoader()
        try await saturate(loader)

        let waiters = (0 ..< 5).map { _ in
            Task {
                await loader.acquireSlotForTesting()
            }
        }

        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 5 }
        waiters[1].cancel()
        waiters[3].cancel()

        #expect(await waiters[1].value == false)
        #expect(await waiters[3].value == false)
        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 3 }

        await loader.releaseSlotForTesting()
        await loader.releaseSlotForTesting()
        await loader.releaseSlotForTesting()

        #expect(await waiters[0].value)
        #expect(await waiters[2].value)
        #expect(await waiters[4].value)

        let snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.maxObservedActiveTasks == snapshot.maxConcurrent)
        #expect(snapshot.pendingContinuations == 0)

        await releaseAllActiveSlots(loader)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    func `cancelAll drains waiters without granting slots`() async throws {
        let loader = ThumbnailLoader()
        try await saturate(loader)

        let waiters = (0 ..< 3).map { _ in
            Task {
                await loader.acquireSlotForTesting()
            }
        }

        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 3 }
        await loader.cancelAll()

        for waiter in waiters {
            #expect(await waiter.value == false)
        }

        let snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.pendingContinuations == 0)
        #expect(snapshot.maxObservedActiveTasks == snapshot.maxConcurrent)

        await releaseAllActiveSlots(loader)
    }

    @Test(.tags(.threadSafety), .timeLimit(.minutes(1)))
    func `FIFO grant skips cancelled waiter`() async throws {
        let loader = ThumbnailLoader()
        try await saturate(loader)

        let first = Task { await loader.acquireSlotForTesting() }
        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 1 }

        let cancelled = Task { await loader.acquireSlotForTesting() }
        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 2 }

        let third = Task { await loader.acquireSlotForTesting() }
        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 3 }

        cancelled.cancel()
        #expect(await cancelled.value == false)
        try await waitForSlotSnapshot(loader) { $0.pendingContinuations == 2 }

        await loader.releaseSlotForTesting()
        #expect(await first.value)

        var snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.pendingContinuations == 1)

        await loader.releaseSlotForTesting()
        #expect(await third.value)

        snapshot = await loader.slotSnapshotForTesting()
        #expect(snapshot.activeTasks == snapshot.maxConcurrent)
        #expect(snapshot.pendingContinuations == 0)
        #expect(snapshot.maxObservedActiveTasks == snapshot.maxConcurrent)

        await releaseAllActiveSlots(loader)
    }
}

private func saturate(_ loader: ThumbnailLoader) async throws {
    let maxConcurrent = await loader.slotSnapshotForTesting().maxConcurrent

    for _ in 0 ..< maxConcurrent {
        let granted = await loader.acquireSlotForTesting()
        #expect(granted)
    }

    try await waitForSlotSnapshot(loader) { snapshot in
        snapshot.activeTasks == snapshot.maxConcurrent
    }
}

private func releaseAllActiveSlots(_ loader: ThumbnailLoader) async {
    await loader.cancelAll()
    let snapshot = await loader.slotSnapshotForTesting()

    for _ in 0 ..< snapshot.activeTasks {
        await loader.releaseSlotForTesting()
    }
}

private func waitForSlotSnapshot(
    _ loader: ThumbnailLoader,
    matching predicate: ((
        activeTasks: Int,
        pendingContinuations: Int,
        maxConcurrent: Int,
        maxObservedActiveTasks: Int,
    )) -> Bool,
) async throws {
    for _ in 0 ..< 100 {
        let snapshot = await loader.slotSnapshotForTesting()
        if predicate(snapshot) {
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    let snapshot = await loader.slotSnapshotForTesting()
    Issue.record(
        "Timed out waiting for slot snapshot. activeTasks=\(snapshot.activeTasks), pendingContinuations=\(snapshot.pendingContinuations), maxConcurrent=\(snapshot.maxConcurrent), maxObservedActiveTasks=\(snapshot.maxObservedActiveTasks)",
    )
    throw SlotSnapshotTimeout()
}

private struct SlotSnapshotTimeout: Error {}
