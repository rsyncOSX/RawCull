import Foundation
import Observation

/// Application-owned reservation for the three existing AI Analysis workflows.
/// Cancellation releases the reservation only after the owned worker terminates.
@Observable @MainActor
final class CombinedReviewLease {
    static let shared = CombinedReviewLease()
    private(set) var owner: UUID?
    @ObservationIgnored var invalidateOwner: (() -> Void)?
    var isHeld: Bool {
        owner != nil
    }

    func acquire(_ id: UUID) throws {
        guard owner == nil else { throw ReviewRunError.invalidTransition }
        owner = id
    }

    @ObservationIgnored private var releaseWaiters: [UUID: CheckedContinuation<Void, any Error>] = [:]

    func release(_ id: UUID) {
        guard owner == id else { return }
        owner = nil; invalidateOwner = nil
        let waiters = releaseWaiters
        releaseWaiters = [:]
        waiters.values.forEach { $0.resume() }
    }

    func invalidate() {
        invalidateOwner?()
    }

    /// Ask the owner to stop and suspend until it releases the lease.
    /// Throws `CancellationError` promptly if the caller is cancelled, so a
    /// cancelled caller neither spins nor goes on to mutate model resources.
    func invalidateAndWait() async throws {
        invalidate()
        guard isHeld else { return }
        let id = UUID()
        try await withTaskCancellationHandler { () async throws in
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if !isHeld {
                    continuation.resume()
                } else {
                    releaseWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.releaseWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }
}
