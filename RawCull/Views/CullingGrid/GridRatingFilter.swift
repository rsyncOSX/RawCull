import AppKit
import RawCullCore
import SwiftUI

enum GridRatingFilter: Hashable {
    case all
    case unrated
    case rating(Int) // -1 = rejected, 0 = keepers, 2–5 = stars
}
