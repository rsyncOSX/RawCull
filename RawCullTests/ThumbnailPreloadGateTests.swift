import Foundation
@testable import RawCull
import Testing

struct ThumbnailPreloadGateTests {
    private let catalog = URL(filePath: "/test/catalog")

    @Test
    func `completed visible file is released while the catalog is still preloading`() async {
        let gate = ThumbnailPreloadGate()
        let session = await gate.begin(catalogURL: catalog)
        let ready = catalog.appendingPathComponent("ready.ARW")
        let pending = catalog.appendingPathComponent("pending.ARW")
        let waiter = Task { await gate.waitUntilGridDecodeIsAvailable(for: ready) }
        await gate.finished(sourceURL: ready, sessionID: session)
        #expect(await waiter.value)
        // A different file must remain blocked, even if its waiter is already cancelled.
        let cancelled = Task { await gate.waitUntilGridDecodeIsAvailable(for: pending) }
        cancelled.cancel()
        #expect(await !cancelled.value)
        await gate.end(session)
        #expect(await gate.waitUntilGridDecodeIsAvailable(for: pending))
    }

    @Test
    func `completion belongs to its own active session`() async {
        let gate = ThumbnailPreloadGate()
        let old = await gate.begin(catalogURL: catalog)
        let current = await gate.begin(catalogURL: catalog)
        let photo = catalog.appendingPathComponent("photo.ARW")
        await gate.finished(sourceURL: photo, sessionID: old)
        let blocked = Task { await gate.waitUntilGridDecodeIsAvailable(for: photo) }
        blocked.cancel()
        #expect(await !blocked.value)
        await gate.end(old)
        await gate.finished(sourceURL: photo, sessionID: old) // Late old completion is ignored.
        await gate.finished(sourceURL: photo, sessionID: current)
        #expect(await gate.waitUntilGridDecodeIsAvailable(for: photo))
        await gate.end(current)
    }

    @Test
    func `other catalogs and failed-file completion never wait for the catalog end`() async {
        let gate = ThumbnailPreloadGate()
        let session = await gate.begin(catalogURL: catalog)
        #expect(await gate.waitUntilGridDecodeIsAvailable(for: URL(filePath: "/other/photo.ARW")))
        let failed = catalog.appendingPathComponent("failed.ARW")
        await gate.finished(sourceURL: failed, sessionID: session)
        #expect(await gate.waitUntilGridDecodeIsAvailable(for: failed))
        await gate.end(session)
    }
}
