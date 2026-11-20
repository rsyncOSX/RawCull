import Foundation
@testable import RawCull
import Testing

@Suite("Cancellable detached work")
struct DetachedCancellableTests {
    @Test
    func `cancelling the caller cancels the detached work`() async {
        let started = AsyncStream<Void>.makeStream()
        let caller = Task {
            await detachedCancellable(priority: .utility) { () -> Bool in
                started.continuation.yield()
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return true
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()

        caller.cancel()

        // Without forwarding, the detached loop would never see cancellation
        // and this await would hang until the test times out.
        #expect(await caller.value == true)
    }

    @Test
    func `throwing variant surfaces cancellation from the detached work`() async {
        let caller = Task {
            try await detachedCancellable(priority: .utility) { () throws -> Int in
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(5))
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(20))
        caller.cancel()

        await #expect(throws: CancellationError.self) {
            try await caller.value
        }
    }

    @Test
    func `uncancelled work returns its value`() async throws {
        #expect(await detachedCancellable { 21 * 2 } == 42)
        #expect(try await detachedCancellable { () throws -> String in "ok" } == "ok")
    }
}
