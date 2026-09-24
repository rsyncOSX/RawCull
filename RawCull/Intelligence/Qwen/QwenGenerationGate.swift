import Foundation

/// Serializes Qwen generations across features sharing one inference runtime.
/// Short cancellable suspensions let queued callers stop promptly.
actor QwenGenerationGate {
    private var held = false

    func acquire() async throws {
        while held {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        held = true
    }

    func release() {
        held = false
    }
}
