//
//  SupportedFileType.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/02/2026.
//

// During search in catalog, the fileextension on
// files retrieved in search is lowercased.
// guard fileURL.pathExtension.lowercased() == SupportedFileType.arw.rawValue else { continue }

enum SupportedFileType: String, CaseIterable {
    case arw
    case jpeg, jpg

    var extensions: [String] {
        switch self {
        case .arw: ["arw"]
        case .jpg: ["jpg"]
        case .jpeg: ["jpeg"]
        }
    }
}
