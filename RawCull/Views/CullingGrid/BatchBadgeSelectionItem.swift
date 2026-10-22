import AppKit
import RawCullCore
import SwiftUI

struct BatchBadgeSelectionItem: Identifiable {
    var id: String {
        label
    }

    let label: String
    let count: Int
    let color: Color
}
