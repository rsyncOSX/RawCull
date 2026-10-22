import OSLog
import RawCullCore
import SwiftUI

nonisolated enum BurstReviewKeyAction: Equatable {
    case previousImage
    case nextImage
    case nextGroup

    nonisolated static func resolve(characters: String?) -> BurstReviewKeyAction? {
        switch characters {
        case "p", "P": .previousImage
        case "n", "N": .nextImage
        case "g", "G": .nextGroup
        default: nil
        }
    }
}
