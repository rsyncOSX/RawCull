import Dispatch
import Foundation
import PhotoAnalysisKit
@testable import RawCull
import Synchronization
import Testing

@Suite("RawCull Vision work serializer")
struct RawCullVisionWorkSerializerTests {
    @Test("PhotoAIKit Vision work waits behind PhotoAnalysisKit's shared gate")
    func sharesPhotoAnalysisKitGate() async throws {
        let release = DispatchSemaphore(value: 0)
        let blockerStarted = DispatchSemaphore(value: 0)
        let blockerFinished = Mutex(false)

        let blocker = Task {
            try await VisionRequestGate.shared.run {
                blockerStarted.signal()
                release.wait()
                blockerFinished.withLock { $0 = true }
            }
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                blockerStarted.wait()
                continuation.resume()
            }
        }

        let follower = Task {
            try await RawCullVisionWorkSerializer().run {
                blockerFinished.withLock { $0 }
            }
        }
        try await Task.sleep(for: .milliseconds(50))
        release.signal()

        try await blocker.value
        // The adapter's body runs only after the gate's earlier body finished.
        #expect(try await follower.value == true)
    }
}
