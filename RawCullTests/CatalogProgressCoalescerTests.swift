@testable import RawCull
import Testing

@MainActor
private final class ProgressTestScheduler {
    var callbacks: [@MainActor @Sendable () -> Void] = []
    var cancellations = 0

    func schedule(_ callback: @escaping @MainActor @Sendable () -> Void) -> CatalogProgressCoalescer<Int>.Cancellation {
        callbacks.append(callback)
        return { [weak self] in self?.cancellations += 1 }
    }

    /// Deliberately runs cancelled callbacks too, exercising generation checks.
    func fire() {
        let pending = callbacks
        callbacks = []
        pending.forEach { $0() }
    }
}

@MainActor
struct CatalogProgressCoalescerTests {
    @Test func `burst publishes initial and exact latest per tick`() {
        let clock = ProgressTestScheduler()
        var values: [Int] = []
        let publisher = CatalogProgressCoalescer(initial: 0, schedule: clock.schedule) { values.append($0) }
        publisher.update(immediately: true) { $0 = 0 }
        for count in 1...809 { publisher.update { $0 = count } }
        #expect(values == [0])
        #expect(clock.callbacks.count == 1)
        clock.fire()
        #expect(values == [0, 809])
        publisher.finish()
        #expect(values == [0, 809])
    }

    @Test func `fast finish flushes before tick and late callbacks cannot overwrite it`() {
        let clock = ProgressTestScheduler()
        var values: [Int] = []
        let publisher = CatalogProgressCoalescer(initial: 0, schedule: clock.schedule) { values.append($0) }
        publisher.update { $0 = 0 }
        publisher.update { $0 = 1 }
        publisher.finish { $0 = 9 }
        clock.fire()
        publisher.update { $0 = 2 }
        #expect(values == [0, 9])
        #expect(clock.cancellations == 1)
    }

    @Test func `cancel and same catalog replacement reject stale callbacks`() {
        let clock = ProgressTestScheduler()
        var displayed = 0
        let old = CatalogProgressCoalescer(initial: 0, schedule: clock.schedule) { displayed = $0 }
        old.update { $0 = 0 }
        old.update { $0 = 100 }
        old.cancel()
        let replacement = CatalogProgressCoalescer(initial: 0, schedule: clock.schedule) { displayed = $0 }
        replacement.update { $0 = 3 }
        clock.fire()
        old.update(immediately: true) { $0 = 999 }
        #expect(displayed == 3)
    }

    @Test func `superseded tick cannot publish a newer window early`() {
        let clock = ProgressTestScheduler()
        var values: [Int] = []
        let publisher = CatalogProgressCoalescer(initial: 0, schedule: clock.schedule) { values.append($0) }
        publisher.update { $0 = 0 }
        publisher.update { $0 = 1 }
        let stale = clock.callbacks.removeFirst()
        publisher.update(immediately: true) { $0 = 2 }
        publisher.update { $0 = 3 }
        stale()
        #expect(values == [0, 2])
        clock.fire()
        #expect(values == [0, 2, 3])
    }

    @Test func `terminal snapshot preserves exact totals and clears ETA`() {
        let clock = ProgressTestScheduler()
        var values: [CatalogThumbnailProgress] = []
        let publisher = CatalogProgressCoalescer(initial: CatalogThumbnailProgress(), schedule: clock.schedule) {
            values.append($0)
        }
        publisher.update(immediately: true) { $0.total = 20 }
        publisher.update {
            $0.completed = 7
            $0.estimatedSeconds = 14
        }
        publisher.finish {
            $0.completed = 20
            $0.total = 20
            $0.estimatedSeconds = 0
        }
        clock.fire()
        #expect(values.count == 2)
        #expect(values.last == CatalogThumbnailProgress(completed: 20, total: 20, estimatedSeconds: 0))
    }

    @Test func `pending tick does not retain publisher`() {
        let clock = ProgressTestScheduler()
        var publisher: CatalogProgressCoalescer<Int>? = CatalogProgressCoalescer(
            initial: 0, schedule: clock.schedule, publish: { _ in },
        )
        weak let weakPublisher = publisher
        publisher?.update { $0 = 0 }
        publisher?.update { $0 = 1 }
        publisher = nil
        #expect(weakPublisher == nil)
        clock.fire()
    }
}
