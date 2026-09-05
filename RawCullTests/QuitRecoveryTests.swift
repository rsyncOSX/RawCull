import AppKit
@testable import RawCull
import Testing

@MainActor
struct QuitRecoveryTests {
    @Test(arguments: [AppDelegate.QuitRecoveryChoice.retry, .cancel, .discard])
    func `failed save offers recovery and replies exactly once`(choice: AppDelegate.QuitRecoveryChoice) async {
        let delegate = AppDelegate()
        var attempts = 0
        var releases = 0
        var replies: [Bool] = []
        var pending = false
        await withCheckedContinuation { continuation in
            let result = delegate.beginTermination(
                flush: {
                    attempts += 1
                    #expect(pending)
                    #expect(releases == 0)
                    return attempts > 1
                },
                chooseRecovery: { choice },
                setPending: { pending = $0 },
                releaseAccess: { releases += 1 },
                reply: {
                    replies.append($0)
                    continuation.resume()
                },
            )
            #expect(result == .terminateLater)
            // Repeated quit requests share the original outstanding reply.
            #expect(delegate.beginTermination(
                flush: { Issue.record("Duplicate save"); return true },
                chooseRecovery: { .discard },
                setPending: { _ in Issue.record("Duplicate request") },
                releaseAccess: { Issue.record("Duplicate release") },
                reply: { _ in Issue.record("Duplicate reply") },
            ) == .terminateLater)
        }
        #expect(attempts == (choice == .retry ? 2 : 1))
        #expect(replies == [choice != .cancel])
        #expect(releases == (choice == .cancel ? 0 : 1))
        #expect(pending == (choice != .cancel))
        if choice == .cancel {
            await withCheckedContinuation { continuation in
                _ = delegate.beginTermination(
                    flush: { true },
                    chooseRecovery: { Issue.record("Unexpected failure"); return .cancel },
                    setPending: { pending = $0 },
                    releaseAccess: { releases += 1 },
                    reply: { #expect($0); continuation.resume() },
                )
            }
            #expect(releases == 1)
        }
    }
}
