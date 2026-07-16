import Foundation
import PhotoAnalysisKit

nonisolated enum SharpnessPhotoType: String, CaseIterable, Codable, Identifiable {
    case auto
    case birdsWildlife
    case portrait
    case landscape
    case generalAction

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .birdsWildlife: "Birds/Wildlife"
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        case .generalAction: "Action"
        }
    }

    nonisolated var packagePreset: SharpnessPreset {
        switch self {
        case .auto:
            .automatic

        case .birdsWildlife:
            .birdsAndWildlife

        case .portrait:
            .portrait

        case .landscape:
            .landscape

        case .generalAction:
            .generalAction
        }
    }
}

nonisolated enum SharpnessScoringQuality: String, CaseIterable, Codable, Identifiable {
    case fast
    case balanced
    case highPrecision

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .highPrecision: "High Precision"
        }
    }

    nonisolated var minimumThumbnailMaxPixelSize: Int {
        switch self {
        case .fast: 512
        case .balanced: 768
        case .highPrecision: 1024
        }
    }

    var maxConcurrentScoringTasks: Int {
        switch self {
        case .fast: 6
        case .balanced: 4
        case .highPrecision: 3
        }
    }

    nonisolated var packageQuality: SharpnessQuality {
        switch self {
        case .fast:
            .fast

        case .balanced:
            .balanced

        case .highPrecision:
            .highPrecision
        }
    }
}

nonisolated enum SharpnessScoringSource: String, CaseIterable, Codable, Identifiable {
    case embeddedPreview
    case rawDemosaic

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .embeddedPreview: "Embedded Preview"
        case .rawDemosaic: "RAW Demosaic"
        }
    }

    var help: String {
        switch self {
        case .embeddedPreview:
            "Scores Sony's embedded camera JPEG preview. Fast and suitable for normal culling."

        case .rawDemosaic:
            "Scores a CIRAWFilter demosaiced image. Much slower, but useful for final precision checks."
        }
    }
}

enum SharpnessScoringSizeOption: Int, CaseIterable, Identifiable {
    case px1024 = 1024
    case px1536 = 1536
    case px2048 = 2048

    nonisolated static let highPrecisionDefaultPixelSize = SharpnessScoringSizeOption.px2048.rawValue
    nonisolated static let maximumPixelSize = SharpnessScoringSizeOption.px2048.rawValue

    var id: Int {
        rawValue
    }

    var title: String {
        switch self {
        case .px1024: "1024 px"
        case .px1536: "1536 px"
        case .px2048: "2048 px"
        }
    }

    nonisolated static func normalizedPixelSize(_ value: Int, for quality: SharpnessScoringQuality) -> Int {
        guard value > 0 else { return maximumPixelSize }
        return min(max(value, quality.minimumThumbnailMaxPixelSize), maximumPixelSize)
    }
}
