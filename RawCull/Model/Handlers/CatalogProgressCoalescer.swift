import Foundation

/// Coalesces presentation only. File accounting and image readiness stay in the pipeline.
/// Each catalog load owns a new instance; cancelled instances reject even queued callbacks.
@MainActor
final class CatalogProgressCoalescer<Value: Equatable & Sendable> {
    typealias Cancellation = @MainActor @Sendable () -> Void
    typealias Scheduler = @MainActor (@escaping @MainActor @Sendable () -> Void) -> Cancellation

    private(set) var latest: Value
    private var published: Value?
    private var pendingCancellation: Cancellation?
    private var scheduledID: UUID?
    private var accepting = true
    private let schedule: Scheduler
    private let publish: @MainActor (Value) -> Void

    init(
        initial: Value,
        schedule: @escaping Scheduler = CatalogProgressCoalescer.scheduleTick,
        publish: @escaping @MainActor (Value) -> Void,
    ) {
        latest = initial
        self.schedule = schedule
        self.publish = publish
    }

    func update(immediately: Bool = false, _ change: (inout Value) -> Void) {
        guard accepting else { return }
        change(&latest)
        if immediately || published == nil {
            flush()
        } else if scheduledID == nil, latest != published {
            let id = UUID()
            scheduledID = id
            pendingCancellation = schedule { [weak self] in
                guard let self, self.accepting, self.scheduledID == id else { return }
                self.flush()
            }
        }
    }

    /// Publish the latest exact state before hiding the progress UI.
    func finish(_ change: (inout Value) -> Void = { _ in }) {
        guard accepting else { return }
        change(&latest)
        flush()
        cancel()
    }

    func cancel() {
        accepting = false
        cancelTick()
    }

    private func flush() {
        cancelTick()
        guard accepting, latest != published else { return }
        published = latest
        publish(latest)
    }

    private func cancelTick() {
        scheduledID = nil
        pendingCancellation?()
        pendingCancellation = nil
    }

    private static func scheduleTick(_ action: @escaping @MainActor @Sendable () -> Void) -> Cancellation {
        let task = Task { @concurrent in
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await action()
        }
        return { task.cancel() }
    }
}

nonisolated struct CatalogThumbnailProgress: Equatable, Sendable {
    var completed = 0
    var total = 0
    var estimatedSeconds = 0
}
