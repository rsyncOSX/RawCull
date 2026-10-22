import AppKit
import RawCullCore
import SwiftUI

nonisolated struct ZoomOverlayNavigationContext: Equatable {
    let orderedFileIDs: [FileItem.ID]

    init(orderedFileIDs: [FileItem.ID]) {
        var seen = Set<FileItem.ID>()
        self.orderedFileIDs = orderedFileIDs.filter { seen.insert($0).inserted }
    }
}
