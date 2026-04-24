//
//  FocusPointsModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import CoreGraphics
import Foundation

struct FocusPointsModel: Identifiable {
    let id: UUID
    let sourceFile: String
    let focusPoints: [FocusPoint]

    init(sourceFile: String, focusLocations: [String]) {
        self.id = UUID()
        self.sourceFile = sourceFile
        self.focusPoints = focusLocations.compactMap { FocusPoint(focusLocation: $0) }
    }
}

struct FocusPoint: Identifiable {
    let id: UUID
    let sensorWidth: CGFloat
    let sensorHeight: CGFloat
    let x: CGFloat
    let y: CGFloat

    init?(focusLocation: String) {
        let parts = focusLocation
            .split(separator: " ")
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        self.id = UUID()
        sensorWidth = CGFloat(parts[0])
        sensorHeight = CGFloat(parts[1])
        x = CGFloat(parts[2])
        y = CGFloat(parts[3])
    }

    /// AF x-coordinate expressed as a fraction of the sensor width.
    /// Formula: `x / sensorWidth` — in `[0, 1]` for well-formed values.
    /// Lets overlays place the marker without knowing the preview's pixel size.
    var normalizedX: CGFloat {
        x / sensorWidth
    }

    /// AF y-coordinate expressed as a fraction of the sensor height.
    /// Formula: `y / sensorHeight` — same 0…1 convention as `normalizedX`.
    var normalizedY: CGFloat {
        y / sensorHeight
    }
}
