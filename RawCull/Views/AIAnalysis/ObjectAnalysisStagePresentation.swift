import AppKit
import SwiftUI

extension ObjectAnalysisStage {
    var label: String {
        switch self {
        case .loadingImage: "Loading image"
        case .discoveringConcepts: "Discovering concepts"
        case .segmenting(let concept, let index, let count): "Segmenting \(concept) (\(index)/\(count))"
        case .preparingObjectBoard: "Preparing object board"
        case .analyzingObjects: "Analyzing objects"
        case .completed: "Complete"
        }
    }
}
