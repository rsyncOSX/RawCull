import Foundation
@testable import RawCull
import Testing

struct ThumbnailPreloadGridGateTests {
    @Test
    func `active preloader blocks only its selected catalog grid`() {
        let active = URL(fileURLWithPath: "/tmp/catalog-a")

        #expect(ThumbnailPreloadGridGate.shouldBlock(
            activeCatalogURL: active,
            selectedCatalogURL: URL(fileURLWithPath: "/tmp/./catalog-a"),
            hasActivePreloader: true,
        ))
        #expect(!ThumbnailPreloadGridGate.shouldBlock(
            activeCatalogURL: active,
            selectedCatalogURL: URL(fileURLWithPath: "/tmp/catalog-b"),
            hasActivePreloader: true,
        ))
    }

    @Test
    func `grid unblocks for every terminal inactive state`() {
        let catalog = URL(fileURLWithPath: "/tmp/catalog")

        #expect(!ThumbnailPreloadGridGate.shouldBlock(
            activeCatalogURL: catalog,
            selectedCatalogURL: catalog,
            hasActivePreloader: false,
        ))
        #expect(!ThumbnailPreloadGridGate.shouldBlock(
            activeCatalogURL: nil,
            selectedCatalogURL: catalog,
            hasActivePreloader: true,
        ))
        #expect(!ThumbnailPreloadGridGate.shouldBlock(
            activeCatalogURL: catalog,
            selectedCatalogURL: nil,
            hasActivePreloader: true,
        ))
    }

    @Test
    func `extraction metrics count duplicate keys cancellation and peak activity`() async {
        let cache = await makeIsolatedCache()
        let first = makeThumbnailRequestKey(url: URL(fileURLWithPath: "/tmp/first.arw"))
        let second = makeThumbnailRequestKey(url: URL(fileURLWithPath: "/tmp/second.arw"))

        #expect(!cache.beginThumbnailExtraction(key: first))
        #expect(cache.beginThumbnailExtraction(key: first))
        #expect(!cache.beginThumbnailExtraction(key: second))
        cache.endThumbnailExtraction(key: first, cancelled: true)
        cache.endThumbnailExtraction(key: first, cancelled: false)
        cache.endThumbnailExtraction(key: second, cancelled: false)

        let metrics = cache.thumbnailExtractionMetrics()
        #expect(metrics.starts == 3)
        #expect(metrics.completions == 3)
        #expect(metrics.cancellations == 1)
        #expect(metrics.duplicateStarts == 1)
        #expect(metrics.coalescedWaiters == 0)
        #expect(metrics.activeExtractions == 0)
        #expect(metrics.maximumActiveExtractions == 3)

        await cache.clearCaches()
        #expect(cache.thumbnailExtractionMetrics().starts == 0)
    }
}
