import Foundation
import Observation
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

@MainActor
@Suite("Zoom navigation projection")
struct ZoomNavigationProjectionTests {
    @Test
    func `selection and repeated presentation reads reuse ordering`() {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        model.catalog.files = [second, first]
        model.catalog.filteredFiles = [second, first]
        let navigation = ZoomNavigationPresentation(viewModel: model)
        model.selection.selectedFileID = first.id
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
        #expect(navigation.currentZoomIndex == 0)
        #expect(!navigation.canNavigatePrevious)
        #expect(navigation.canNavigateNext)
        let builds = model.catalogController.zoomNavigationBuildCount
        model.selection.selectedFileID = second.id
        #expect(navigation.currentZoomIndex == 1)
        #expect(navigation.canNavigatePrevious)
        #expect(!navigation.canNavigateNext)
        #expect(model.catalogController.zoomNavigationBuildCount == builds)
        model.selection.selectedFileID = UUID()
        #expect(navigation.currentZoomIndex == nil)
    }

    @Test
    func `context preserves supplied order and missing context falls back`() {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        model.catalog.files = [first, second]
        model.catalog.filteredFiles = [first, second]
        model.ratings.ratingFilter = .stars(5)
        model.zoomOverlay.navigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [second.id, UUID(), first.id])
        let navigation = ZoomNavigationPresentation(viewModel: model)
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.zoomOverlay.navigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [UUID()])
        #expect(navigation.orderedZoomFiles.isEmpty)
        model.ratings.ratingFilter = .all
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
    }

    @Test
    func `rating changes and analysis modes invalidate cached order`() {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        model.catalog.files = [second, first]
        model.catalog.filteredFiles = [second, first]
        let navigation = ZoomNavigationPresentation(viewModel: model)
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
        model.sharpnessModel.sortBySharpness = true
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.sharpnessModel.sortBySharpness = false
        model.similarityModel.sortBySimilarity = true
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.ratings.ratingFilter = .stars(3)
        model.ratings.ratingCache = [first.name: 3]
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id])
        model.ratings.ratingCache[second.name] = 3
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.catalog.filteredFiles = [first, second]
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
    }

    @Test
    func `catalog replacement refreshes contextual values even for retained IDs`() {
        let model = makeRawCullViewModel()
        var file = makeCullingTestFile("A.ARW")
        model.catalog.files = [file]
        model.catalog.filteredFiles = [file]
        model.selection.selectedFileID = file.id
        model.zoomOverlay.navigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [file.id])
        let navigation = ZoomNavigationPresentation(viewModel: model)
        #expect(navigation.orderedZoomFiles.first?.size == file.size)
        file = FileItem(
            id: file.id,
            url: file.url,
            name: file.name,
            size: file.size + 100,
            dateModified: file.dateModified,
            exifData: file.exifData,
            afFocusNormalized: file.afFocusNormalized,
        )
        model.catalog.files = [file]
        #expect(navigation.orderedZoomFiles.first?.size == file.size)
        model.catalog.files = []
        #expect(navigation.currentZoomIndex == nil)
        model.catalog.filteredFiles = []
        #expect(navigation.orderedZoomFiles.isEmpty)
        #expect(!navigation.canNavigateNext)
        #expect(!navigation.canNavigatePrevious)
    }

    @Test
    func `cache hits preserve observation of ordering inputs`() {
        let model = makeRawCullViewModel()
        let file = makeCullingTestFile("A.ARW")
        model.catalog.files = [file]
        model.catalog.filteredFiles = [file]
        _ = model.catalogController.zoomNavigationProjection()
        let changed = Mutex(false)
        withObservationTracking {
            _ = model.catalogController.zoomNavigationProjection()
        } onChange: {
            changed.withLock { $0 = true }
        }
        model.catalog.filteredFiles = []
        #expect(changed.withLock { $0 })
        #expect(model.catalogController.zoomNavigationProjection().files.isEmpty)
    }
}
