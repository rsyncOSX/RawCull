//
//  ThumbnailError.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/02/2026.
//

//
//  ThumbnailError.swift
//  RawCull
//

import Foundation

enum ThumbnailError: Error, LocalizedError {
    case invalidSource
    case generationFailed
    case contextCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "Could not create an image source from the provided URL."

        case .generationFailed:
            "Failed to generate or render the thumbnail image."

        case .contextCreationFailed:
            "Failed to create a CGContext for thumbnail re-rendering."
        }
    }
}
