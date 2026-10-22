import SwiftUI

nonisolated enum LoupeImageKeyAction: Equatable {
    case zoomIn
    case zoomOut
    case toggleEmbeddedJPG
    case toggleDevelopedRAW
    case toggleFocusMask
    case toggleSubjectOutline
    case toggleFocusPoints
    case toggleMetadata
    case inspectActualPixels

    nonisolated static func resolve(characters: String?) -> LoupeImageKeyAction? {
        if let sharedAction = ImageReviewKeyboardPolicy.action(for: characters) {
            return switch sharedAction {
            case .zoomIn: .zoomIn
            case .zoomOut: .zoomOut
            case .toggleEmbeddedJPG: .toggleEmbeddedJPG
            case .toggleDevelopedRAW: .toggleDevelopedRAW
            case .toggleFocusMask: .toggleFocusMask
            case .toggleSubjectOutline: .toggleSubjectOutline
            case .toggleFocusPoints: .toggleFocusPoints
            case .rating: nil
            }
        }

        return switch characters {
        case "e", "E":
            .toggleMetadata

        case "z", "Z":
            .inspectActualPixels

        default:
            nil
        }
    }
}
