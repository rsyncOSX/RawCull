import Foundation

enum SharpnessPhotoType: String, CaseIterable, Codable, Identifiable {
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

    nonisolated func applying(to config: FocusDetectorConfig) -> FocusDetectorConfig {
        var c = config
        switch self {
        case .auto:
            return c

        case .birdsWildlife:
            c.preBlurRadius = 2.2
            c.borderInsetFraction = 0.05
            c.salientWeight = 0.85
            c.explicitSalientWeightOverride = 0.85
            c.subjectSizeFactor = 0.05
            c.silhouettePenaltyStrength = 0.55
            c.afRegionRadius = 0.06
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true

        case .portrait:
            c.preBlurRadius = min(c.preBlurRadius, 1.7)
            c.salientWeight = 0.80
            c.explicitSalientWeightOverride = 0.80
            c.subjectSizeFactor = 0.08
            c.silhouettePenaltyStrength = 0.25
            c.afRegionRadius = 0.10
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true

        case .landscape:
            c.preBlurRadius = min(c.preBlurRadius, 1.55)
            c.salientWeight = 0.35
            c.explicitSalientWeightOverride = 0.35
            c.subjectSizeFactor = 0.0
            c.silhouettePenaltyStrength = 0.15
            c.afRegionRadius = 0.0
            c.isolateMaskToSubject = false

        case .generalAction:
            c.preBlurRadius = 2.0
            c.salientWeight = 0.65
            c.explicitSalientWeightOverride = 0.65
            c.subjectSizeFactor = 0.05
            c.silhouettePenaltyStrength = 0.40
            c.afRegionRadius = 0.09
            c.enableSubjectClassification = true
            c.isolateMaskToSubject = true
        }
        return c
    }
}

enum SharpnessScoringQuality: String, CaseIterable, Codable, Identifiable {
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

    nonisolated func applying(to config: FocusDetectorConfig) -> FocusDetectorConfig {
        var c = config
        switch self {
        case .fast:
            c.fineDetailBlendWeight = 0.0

        case .balanced:
            c.fineDetailBlendWeight = max(c.fineDetailBlendWeight, 0.25)

        case .highPrecision:
            c.fineDetailBlendWeight = max(c.fineDetailBlendWeight, 0.45)
            c.enableSubjectClassification = true
        }
        return c
    }
}

enum SharpnessScoringSource: String, CaseIterable, Codable, Identifiable {
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
