//
//  NikonRawFormat.swift
//  RawCull
//
//  `RawFormat` conformer for Nikon NEF. Delegates thumbnail and full-res
//  JPEG extraction to the dedicated extractors; full-res extraction uses
//  ImageIO first with a binary TIFF-walk fallback for NEFs whose preview
//  JPEG is not surfaced as a top-level image index.
//

import CoreGraphics
import Foundation

enum NikonRawFormat: RawFormat {
    nonisolated static let extensions: Set<String> = ["nef"]
    // nonisolated static let displayName: String = "Nikon NEF"

    // MARK: - Thumbnail

    nonisolated static func extractThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) async throws -> CGImage {
        try await NikonThumbnailExtractor.extractNikonThumbnail(
            from: url,
            maxDimension: maxDimension,
            qualityCost: qualityCost,
        )
    }

    // MARK: - Full-resolution embedded JPEG

    nonisolated static func extractFullJPEG(from url: URL, fullSize: Bool) async -> CGImage? {
        await JPGNikonNEFExtractor.jpgNikonNEFExtractor(from: url, fullSize: fullSize)
    }

    // MARK: - AF focus location

    nonisolated static func focusLocation(from url: URL) -> String? {
        NikonMakerNoteParser.focusLocation(from: url)
    }

    // MARK: - Compression + size class

    /// Nikon TIFF Compression tag values seen in NEF files.
    nonisolated static func rawFileTypeString(compressionCode: Int) -> String {
        switch compressionCode {
        case 1: "Uncompressed"
        case 34713: "NEF Compressed" // lossy or lossless depending on body/version
        case 34892: "Lossy NEF"
        default: "Unknown (\(compressionCode))"
        }
    }

    /// Nikon Z-series + D850 MP thresholds. Z9/Z8/Z7/D850 are ~45 MP; Z6 is ~24 MP.
    nonisolated static func sizeClassThresholds(camera: String) -> (L: Double, M: Double) {
        let upper = camera.uppercased()
        if upper.contains("Z 9") || upper.contains("Z9") { return (40, 18) } // Z9: 45/25/11 MP
        if upper.contains("Z 8") || upper.contains("Z8") { return (40, 18) } // Z8: 45/25/11 MP
        if upper.contains("Z 7") || upper.contains("Z7") { return (40, 18) } // Z7/Z7 II: 45/25/11 MP
        if upper.contains("Z 6") || upper.contains("Z6") { return (22, 11) } // Z6/Z6 II/III: 24/14/6 MP
        if upper.contains("D850") { return (40, 18) } // D850: 45/25/11 MP
        return (25, 10) // generic fallback
    }
}
