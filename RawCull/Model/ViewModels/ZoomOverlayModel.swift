import AppKit
import CoreGraphics
import Foundation
import Observation
import OSLog
import RawCullCore

/// Owns the in-window zoom overlay: whether it is shown, how it navigates, and
/// the images it displays. Choosing the navigation axis depends on the main view
/// mode, so `RawCullViewModel.openZoomOverlay` decides it and passes it in.
@Observable @MainActor
final class ZoomOverlayModel {
    var isVisible = false
    var navigationAxis: ZoomOverlayNavigationAxis = .horizontal
    var navigationContext: ZoomOverlayNavigationContext? {
        didSet { contextRevision &+= 1 }
    }

    /// Advances whenever `navigationContext` changes; part of the zoom
    /// navigation projection key.
    private(set) var contextRevision: UInt64 = 0
    var launchContext: ZoomOverlayLaunchContext = .default
    var nativeSize: CGSize?
    var rawIsReduced: Bool?
    var rawRenderSeconds: Double?
    var cgImage: CGImage?
    var analysisCGImage: CGImage?
    var nsImage: NSImage?
    /// In-flight ARW→JPEG extraction or thumbnail load task for the zoom overlay.
    /// Cancelled when the overlay closes or a new file is opened for zoom.
    var extractionTask: Task<Void, Never>?

    func open(
        axis: ZoomOverlayNavigationAxis,
        navigationIDs: [FileItem.ID]?,
        initialSource: ImagePreviewSource,
        initialZoomMode: ZoomOverlayInitialZoomMode,
        showFocusPointsOnOpen: Bool,
    ) {
        navigationAxis = axis
        navigationContext = navigationIDs.map(ZoomOverlayNavigationContext.init(orderedFileIDs:))
        launchContext = ZoomOverlayLaunchContext(
            initialSource: initialSource,
            initialZoomMode: initialZoomMode,
            showFocusPointsOnOpen: showFocusPointsOnOpen,
        )
        isVisible = true
    }

    func close() {
        extractionTask?.cancel()
        extractionTask = nil
        isVisible = false
        navigationContext = nil
        launchContext = .default
        cgImage = nil
        nativeSize = nil
        rawIsReduced = nil
        rawRenderSeconds = nil
        analysisCGImage = nil
        nsImage = nil
    }
}
