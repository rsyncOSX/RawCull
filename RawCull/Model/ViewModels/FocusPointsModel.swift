//
//  FocusPointsModel.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import AppKit
import SwiftUI

struct FocusPointsModel: Identifiable {
    let id = UUID()
    let sourceFile: String
    let focusPoints: [FocusPoint]

    init(sourceFile: String, focusLocations: [String]) {
        self.sourceFile = sourceFile
        self.focusPoints = focusLocations.compactMap { FocusPoint(focusLocation: $0) }
    }
}

struct FocusPoint: Identifiable {
    let id = UUID()
    let sensorWidth: CGFloat
    let sensorHeight: CGFloat
    let x: CGFloat
    let y: CGFloat

    init?(focusLocation: String) {
        let parts = focusLocation
            .split(separator: " ")
            .compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        sensorWidth = CGFloat(parts[0])
        sensorHeight = CGFloat(parts[1])
        x = CGFloat(parts[2])
        y = CGFloat(parts[3])
    }

    var normalizedX: CGFloat {
        x / sensorWidth
    }

    var normalizedY: CGFloat {
        y / sensorHeight
    }
}

extension CGFloat {
    static let focusMarkerThumbnail: CGFloat = 14 // grid cell ~160pt wide
    static let focusMarkerMedium: CGFloat = 32 // inspector / filmstrip
    static let focusMarkerFullscreen: CGFloat = 64 // extracted JPG / detail view
}
