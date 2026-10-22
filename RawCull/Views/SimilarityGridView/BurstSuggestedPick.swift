import OSLog
import SwiftUI

struct BurstSuggestedPick: Identifiable {
    let groupID: Int
    let file: FileItem
    let subject: String?
    var id: FileItem.ID {
        file.id
    }
}
