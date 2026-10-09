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

    func release(_ id: UUID) {
        guard owner == id else { return }
        owner = nil; invalidateOwner = nil
    }

    func invalidate() {
        invalidateOwner?()
    }

    func invalidateAndWait() async {
        invalidate()
        while isHeld {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
