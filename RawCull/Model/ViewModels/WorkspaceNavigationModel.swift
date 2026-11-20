import Foundation
import Observation
import OSLog
import RawCullCore

/// Which main view fills the window, and opening and closing the zoom overlay
/// from it. The zoom axis follows the main view mode, so both live here.
@Observable @MainActor
final class WorkspaceNavigationModel {
    @ObservationIgnored private let zoomOverlay: ZoomOverlayModel
    @ObservationIgnored private let catalog: CatalogWorkspace
    @ObservationIgnored private let similarityModel: SimilarityScoringModel

    /// Main content mode — drives which view fills the main window.
    var mainViewMode: MainViewMode = .loupe

    init(zoomOverlay: ZoomOverlayModel, catalog: CatalogWorkspace, similarityModel: SimilarityScoringModel) {
        self.zoomOverlay = zoomOverlay
        self.catalog = catalog
        self.similarityModel = similarityModel
    }

    var canShowThumbnailWorkspace: Bool {
        catalog.selectedSource != nil
    }

    var showsBurstGroups: Bool {
        mainViewMode == .similarityGrid && similarityModel.burstModeActive
    }

    func openZoomOverlay(
        navigationIDs: [FileItem.ID]? = nil,
        initialSource: ImagePreviewSource = .embeddedJPG,
        initialZoomMode: ZoomOverlayInitialZoomMode = .fit,
        showFocusPointsOnOpen: Bool = false,
    ) {
        Logger.process.debugMessageOnly("WorkspaceNavigationModel.openZoomOverlay()")
        zoomOverlay.open(
            axis: mainViewMode == .loupe ? .vertical : .horizontal,
            navigationIDs: navigationIDs,
            initialSource: initialSource,
            initialZoomMode: initialZoomMode,
            showFocusPointsOnOpen: showFocusPointsOnOpen,
        )
    }

    func closeZoomOverlay() {
        Logger.process.debugMessageOnly("WorkspaceNavigationModel.closeZoomOverlay()")
        zoomOverlay.close()
    }

    func selectMainViewMode(_ mode: MainViewMode) {
        Logger.process.debugMessageOnly("WorkspaceNavigationModel.selectMainViewMode()")
        closeZoomOverlay()
        if mode != .similarityGrid {
            similarityModel.burstModeActive = false
        }
        mainViewMode = mode
    }
}
