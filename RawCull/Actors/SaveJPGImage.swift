//
//  SaveJPGImage.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/02/2026.
//

import Foundation
import ImageIO
import OSLog
import RawParserKit
import UniformTypeIdentifiers

actor SaveJPGImage {
    /// Saves pre-encoded JPEG data into a selected destination catalog.
    func save(
        _ jpegData: Data,
        originalURL: URL,
        destinationCatalogURL: URL,
        exportMode: ExtractJPGExportMode,
    ) async throws {
        let outputURL = Self.outputURL(
            for: originalURL,
            in: destinationCatalogURL,
            exportMode: exportMode,
        )

        Logger.process.info("ExtractEmbeddedPreview: Attempting to save to \(outputURL.path)")

        try await Task.detached(priority: .background) {
            var candidate = outputURL
            var suffix = 1
            while true {
                try Task.checkCancellation()
                do {
                    // Exclusive creation is enforced by the filesystem, including
                    // case-insensitive collisions and simultaneous exporters.
                    try jpegData.write(to: candidate, options: .withoutOverwriting)
                    break
                } catch CocoaError.fileWriteFileExists {
                    candidate = outputURL.deletingLastPathComponent()
                        .appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent) (\(suffix)).jpg")
                    suffix += 1
                }
            }
            Logger.process.info("ExtractEmbeddedPreview: Successfully saved JPEG. Output bytes: \(jpegData.count)")
        }.value
    }

    nonisolated static func outputURL(
        for originalURL: URL,
        in destinationCatalogURL: URL,
        exportMode: ExtractJPGExportMode,
    ) -> URL {
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let outputName: String = switch exportMode {
        case .embeddedJPG:
            baseName

        case .demosaicedRAW:
            "\(baseName)_demosaic"
        }

        return destinationCatalogURL
            .appendingPathComponent(outputName)
            .appendingPathExtension(RawParserKit.SupportedFileType.jpg.rawValue)
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
