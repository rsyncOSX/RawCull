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
        model.files = [second, first]
        model.filteredFiles = [second, first]
        let navigation = ZoomNavigationPresentation(viewModel: model)
        model.selectedFileID = first.id
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
        #expect(navigation.currentZoomIndex == 0)
        #expect(!navigation.canNavigatePrevious)
        #expect(navigation.canNavigateNext)
        let builds = model.zoomNavigationBuildCount
        model.selectedFileID = second.id
        #expect(navigation.currentZoomIndex == 1)
        #expect(navigation.canNavigatePrevious)
        #expect(!navigation.canNavigateNext)
        #expect(model.zoomNavigationBuildCount == builds)
        model.selectedFileID = UUID()
        #expect(navigation.currentZoomIndex == nil)
    }

    @Test
    func `context preserves supplied order and missing context falls back`() {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        model.files = [first, second]
        model.filteredFiles = [first, second]
        model.ratingFilter = .stars(5)
        model.zoomOverlayNavigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [second.id, UUID(), first.id])
        let navigation = ZoomNavigationPresentation(viewModel: model)
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.zoomOverlayNavigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [UUID()])
        #expect(navigation.orderedZoomFiles.isEmpty)
        model.ratingFilter = .all
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
    }

    @Test
    func `rating changes and analysis modes invalidate cached order`() {
        let model = makeRawCullViewModel()
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        model.files = [second, first]
        model.filteredFiles = [second, first]
        let navigation = ZoomNavigationPresentation(viewModel: model)
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
        model.sharpnessModel.sortBySharpness = true
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.sharpnessModel.sortBySharpness = false
        model.similarityModel.sortBySimilarity = true
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.ratingFilter = .stars(3)
        model.ratingCache = [first.name: 3]
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id])
        model.ratingCache[second.name] = 3
        #expect(navigation.orderedZoomFiles.map(\.id) == [second.id, first.id])
        model.filteredFiles = [first, second]
        #expect(navigation.orderedZoomFiles.map(\.id) == [first.id, second.id])
    }

    @Test
    func `catalog replacement refreshes contextual values even for retained IDs`() {
        let model = makeRawCullViewModel()
        var file = makeCullingTestFile("A.ARW")
        model.files = [file]
        model.filteredFiles = [file]
        model.selectedFileID = file.id
        model.zoomOverlayNavigationContext = ZoomOverlayNavigationContext(orderedFileIDs: [file.id])
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
        model.files = [file]
        #expect(navigation.orderedZoomFiles.first?.size == file.size)
        model.files = []
        #expect(navigation.currentZoomIndex == nil)
        model.filteredFiles = []
        #expect(navigation.orderedZoomFiles.isEmpty)
        #expect(!navigation.canNavigateNext)
        #expect(!navigation.canNavigatePrevious)
    }

    @Test
    func `cache hits preserve observation of ordering inputs`() {
        let model = makeRawCullViewModel()
        let file = makeCullingTestFile("A.ARW")
        model.files = [file]
        model.filteredFiles = [file]
        _ = model.zoomNavigationProjection()
        let changed = Mutex(false)
        withObservationTracking {
            _ = model.zoomNavigationProjection()
        } onChange: {
            changed.withLock { $0 = true }
        }
        model.filteredFiles = []
        #expect(changed.withLock { $0 })
        #expect(model.zoomNavigationProjection().files.isEmpty)
    }
}
