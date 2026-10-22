import OSLog
import RawCullCore
import SwiftUI

nonisolated struct BurstFrameCacheKey: Hashable {
    let fileID: FileItem.ID
    let source: ImagePreviewSource
}
