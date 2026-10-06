import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
struct CatalogConcurrencyTests {
    @Test(arguments: [false, true])
    func `Abort invalidates a pending transition even when persistence fails`(fails: Bool) async throws {
        let viewModel = makeRawCullViewModel()
        let started = CatalogTestGate()
        let release = CatalogTestGate()
        viewModel.cullingModel = CullingModel(
            saveDelayNanoseconds: 60_000_000_000,
            saveHandler: { _ in
                await started.open()
                await release.wait()
                if fails { throw CocoaError(.fileWriteUnknown) }
            }
        )
        let old = ARWSourceCatalog(name: "old", url: URL(filePath: "/tmp/old"))
        let new = ARWSourceCatalog(name: "new", url: URL(filePath: "/tmp/new"))
        viewModel.currentSelectedSource = old
        viewModel.selectedSource = new
        viewModel.cullingModel.updateRating(fileName: "photo.arw", rating: 1, in: old.url)
        var starts: [URL] = []
        viewModel.startSecurityScopedResource = { starts.append($0); return true }
        viewModel.stopSecurityScopedResource = { _ in }
        viewModel.startCatalogLoad(for: new)
        let pending = try #require(viewModel.catalogTransitionTask)
        await started.wait()
        viewModel.abort()
        release.open()
        await pending.value
        #expect(starts.isEmpty)
        #expect(viewModel.catalogTransitionTask == nil)
        #expect(viewModel.catalogLoadTask == nil)
        #expect(viewModel.selectedSource == new)
        #expect(!viewModel.scanning)
    }
}

/// Latched signals control interleavings without timing assumptions.
@MainActor
final class CatalogTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
