import AppKit
import RawCullCore
import SwiftUI

nonisolated enum ZoomOverlayImagePolicy {
    nonisolated static func analysisImage(
        dedicatedAnalysisImage: CGImage?,
        displayImage: CGImage?,
    ) -> CGImage? {
        dedicatedAnalysisImage ?? displayImage
    }
}
