//
//  SaveJPGImage.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

actor SaveJPGImage {
    /// Saves pre-encoded JPEG data next to the source RAW file.
    /// - Parameters:
    ///   - jpegData: JPEG data encoded by the caller before crossing actor boundaries.
    ///   - originalURL: The URL of the source ARW file (used to generate the filename).
    func save(_ jpegData: Data, originalURL: URL) async {
        let outputURL = originalURL.deletingPathExtension().appendingPathExtension("jpg")

        Logger.process.info("ExtractEmbeddedPreview: Attempting to save to \(outputURL.path)")

        await Task.detached(priority: .background) {
            do {
                try jpegData.write(to: outputURL, options: .atomic)
                Logger.process.info("ExtractEmbeddedPreview: Successfully saved JPEG. Output bytes: \(jpegData.count)")
            } catch {
                Logger.process.error("ExtractEmbeddedPreview: Failed to write JPEG at \(outputURL.path): \(error)")
            }
        }.value
    }

    /// Encodes a `CGImage` to JPEG data at export quality.
    /// Call this before sending the result to the save actor so `CGImage` does not
    /// cross actor/task boundaries.
    nonisolated static func jpegData(from image: CGImage) -> Data? {
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 1.0
        ]

        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
