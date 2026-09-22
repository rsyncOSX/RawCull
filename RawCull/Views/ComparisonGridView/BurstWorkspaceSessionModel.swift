import AppKit
import Observation
import RawCullCore

@MainActor
@Observable
final class BurstWorkspaceSessionModel {
    var imageCache: [BurstFrameCacheKey: ComparisonImageState] = [:]
    var viewportState = ComparisonViewportInteractionState()
    var sourceSelection = ImageSourceSelectionState(initialSource: .embeddedJPG)
    var showSubjectOutline = false
    var subjectOutline: CGImage?
    var subjectOutlineFileID: FileItem.ID?
    private(set) var focusConfigurationRevision = 0

    @ObservationIgnored var overlayKeyMonitor: Any?

    func cachedWindowIndices(selectedIndex: Int, itemCount: Int) -> [Int] {
        BurstFrameCachePolicy.indices(around: selectedIndex, itemCount: itemCount)
    }

    func invalidateFocusAnalysis() {
        for key in imageCache.keys {
            imageCache[key]?.focusMask = nil
            imageCache[key]?.isFocusAnalysisComplete = false
        }
        focusConfigurationRevision += 1
    }

    func resetForGroupChange() {
        showSubjectOutline = false
        subjectOutline = nil
        subjectOutlineFileID = nil
        imageCache = [:]
        viewportState = ComparisonViewportInteractionState()
        sourceSelection.resetForNewImage()
    }

    func cancel() {
        if let overlayKeyMonitor {
            NSEvent.removeMonitor(overlayKeyMonitor)
            self.overlayKeyMonitor = nil
        }
    }
}
