import Foundation
import Observation
@testable import RawCull
import RawCullCore
import SwiftUI
import Synchronization
import Testing

@MainActor
@Suite("Review view boundaries")
struct ReviewViewBoundaryTests {
    @Test func `zoom controls observe session viewport instead of unrelated loupe zoom`() {
        let viewModel = makeRawCullViewModel()
        let session = ZoomSessionModel()
        let controls = ZoomOverlayControls(
            viewModel: viewModel, session: session, hasFocusTarget: false,
            onRate: { _ in }, onZoomOut: {}, onZoomReset: {}, onZoomIn: {},
        )
        let changes = Mutex(0)
        withObservationTracking {
            _ = controls.body
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        viewModel.scale = 2
        #expect(changes.withLock { $0 } == 0)
        session.viewport.scale = 2
        #expect(changes.withLock { $0 } == 1)
    }

    @Test func `burst header observes catalog changes independently of viewport changes`() {
        let viewModel = makeRawCullViewModel()
        let header = BurstWorkspaceHeader(viewModel: viewModel, groupID: 1, sortByAFPoint: .constant(false))
        let changes = Mutex(0)
        withObservationTracking {
            _ = header.body
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        viewModel.scale = 2
        #expect(changes.withLock { $0 } == 0)
        viewModel.selectedSource = ARWSourceCatalog(name: "New catalog", url: URL(filePath: "/tmp/new-catalog"))
        #expect(changes.withLock { $0 } == 1)
    }

    @Test func `loupe image content observes source changes independently of inactive preview images`() {
        let session = LoupeSessionModel()
        session.selectSource(.embeddedJPG)
        let content = LoupeImageContent(session: session, url: URL(filePath: "/tmp/image.ARW"), thumbnailSizePreview: 512)
        let changes = Mutex(0)
        withObservationTracking {
            _ = content.body
        } onChange: {
            changes.withLock { $0 += 1 }
        }
        session.thumbnailImage = NSImage(size: NSSize(width: 32, height: 32))
        #expect(changes.withLock { $0 } == 0)
        session.selectSource(.developedRAW)
        #expect(changes.withLock { $0 } == 1)
        session.cancel()
    }

    @Test(arguments: [520.0, 1024.0])
    func `extracted review sections render at narrow and desktop widths`(width: Double) throws {
        let viewModel = makeRawCullViewModel()
        let session = ZoomSessionModel()
        let content = VStack(spacing: 16) {
            BurstWorkspaceHeader(viewModel: viewModel, groupID: 1, sortByAFPoint: .constant(false))
            BurstWorkspaceFilmstrip(
                viewModel: viewModel, files: [], analysis: nil, burstNumber: 1,
                canNavigatePrevious: false, canNavigateNext: false, navigate: { _ in },
            )
            ZoomOverlayControls(
                viewModel: viewModel, session: session, hasFocusTarget: false,
                onRate: { _ in }, onZoomOut: {}, onZoomReset: {}, onZoomIn: {},
            )
        }
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: content)
        let image = try #require(renderer.cgImage)
        #expect(image.width == Int(width))
        #expect(image.height > 144)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RawCullReviewViewSnapshots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("review-sections-\(Int(width)).png")
        try ReviewImageSource.pngData(for: image).write(to: url)
    }
}
