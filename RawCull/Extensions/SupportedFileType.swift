//
//  SupportedFileType.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/02/2026.
//

enum SupportedFileType: String, CaseIterable {
    case arw
    case jpeg, jpg
    // case tiff, tif

    var extensions: [String] {
        switch self {
        case .arw: ["arw"]
        case .jpg: ["jpg"]
        case .jpeg: ["jpeg"]
            // case .tiff: return ["tiff"]
            // case .jpeg: return ["jpeg"]
            // case .tif: return ["tif"]
            //
        }
    }
}
