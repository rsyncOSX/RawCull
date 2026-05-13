import SwiftUI

struct ComparisonImageState: Identifiable {
    let id: FileItem.ID
    var cgImage: CGImage?
    var nsImage: NSImage?
    var focusMask: CGImage?
    var isLoading = false
}
