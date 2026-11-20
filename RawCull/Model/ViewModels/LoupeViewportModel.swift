import CoreGraphics
import Foundation
import Observation
import OSLog

/// Pan and zoom of the main loupe image.
///
/// Owned by the workspace root rather than by `LoupeSessionModel`: the session
/// is `@State` of `LoupeMainImageView` and is recreated with the view, while the
/// loupe viewport has always survived switching main view modes.
@Observable @MainActor
final class LoupeViewportModel {
    var scale: CGFloat = 1.0
    var lastScale: CGFloat = 1.0
    var offset: CGSize = .zero
    var lastOffset: CGSize = .zero

    func reset() {
        Logger.process.debugMessageOnly("LoupeViewportModel.reset()")
        scale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}
