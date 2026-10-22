import AppKit
import RawCullCore
import SwiftUI

nonisolated struct ZoomViewportTransform: Equatable {
    var scale: CGFloat
    var offset: CGSize
}
