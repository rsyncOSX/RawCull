import Foundation
@testable import RawCull
import RawCullCore
import Testing

@MainActor
struct CatalogConcurrencyTests {
    @Test
    func `Old sort cannot publish or finish a newer sort`() async {
        let model = makeRawCullViewModel()
        let firstStarted = CatalogTestGate()
        let secondStarted = CatalogTestGate()
        let firstRelease = CatalogTestGate()
        let secondRelease = CatalogTestGate()
        let old = catalogTestFile("old.arw")
        let new = catalogTestFile("new.arw")
        var calls = 0
        model.sortFiles = { files, _, _ in
            calls += 1
            if calls == 1 {
                firstStarted.open(); await firstRelease.wait()
            } else {
                secondStarted.open(); await secondRelease.wait()
            }
            return files
        }
        model.files = [old]
        let first = Task { await model.handleSortOrderChange() }
        await firstStarted.wait()
        model.files = [new]
        let second = Task { await model.handleSortOrderChange() }
        await secondStarted.wait()
        firstRelease.open()
        await first.value
        #expect(model.filteredFiles.isEmpty)
        #expect(model.isSorting)
        secondRelease.open()
        await second.value
        #expect(model.filteredFiles.map(\.id) == [new.id])
        #expect(!model.isSorting)
    }

    @Test(arguments: [false, true])
    func `Cancelled or catalog-stale sort cannot publish`(switchCatalog: Bool) async {
        let model = makeRawCullViewModel()
        let started = CatalogTestGate()
        let release = CatalogTestGate()
        model.files = [catalogTestFile("old.arw")]
        model.sortFiles = { files, _, _ in
            started.open()
            await release.wait()
            return files
        }
        let task = Task { await model.handleSortOrderChange() }
        await started.wait()
        if switchCatalog {
            model.selectedSource = ARWSourceCatalog(name: "new", url: URL(filePath: "/tmp/new"))
            model.similarityCatalogGeneration &+= 1
        } else {
            task.cancel()
        }
        release.open()
        await task.value
        #expect(model.filteredFiles.isEmpty)
        #expect(!model.isSorting)
    }

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
                if fails {
                    throw CocoaError(.fileWriteUnknown)
                }
            },
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
        if opened {
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

@MainActor
private func catalogTestFile(_ name: String) -> FileItem {
    FileItem(url: URL(filePath: "/tmp/" + name), name: name, size: 1,
             dateModified: Date(), exifData: nil, afFocusNormalized: nil)
}
