//
//  SaveJPGImage.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

import Foundation
@preconcurrency import ImageIO
import OSLog
import UniformTypeIdentifiers

actor SaveJPGImage {
    /// Saves the extracted CGImage to disk as a JPEG.
    /// - Parameters:
    ///   - image: The CGImage to save.
    ///   - originalURL: The URL of the source ARW file (used to generate the filename).
    @concurrent
    nonisolated func save(image: CGImage, originalURL: URL) async {
        let outputURL = originalURL.deletingPathExtension().appendingPathExtension("jpg")

        Logger.process.info("ExtractEmbeddedPreview: Attempting to save to \(outputURL.path)")

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            Logger.process.error("ExtractEmbeddedPreview: Failed to create image destination at \(outputURL.path)")
            return
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        let success = CGImageDestinationFinalize(destination)

        if success {
            // Log the actual output size for verification
            Logger.process.info("ExtractEmbeddedPreview: Successfully saved JPEG. Output Dimensions: \(image.width)x\(image.height)")
        } else {
            Logger.process.error("ExtractEmbeddedPreview: Failed to finalize image writing")
        }
    }
}
