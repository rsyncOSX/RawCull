//
//  SonyRawFormat.swift
//  RawCull
//
//  Thin `RawFormat` conformer that forwards to the existing Sony enums
//  (`SonyThumbnailExtractor`, `JPGSonyARWExtractor`, `SonyMakerNoteParser`).
//  Sony-specific compression codes and A-series size-class thresholds live
//  here so that per-vendor knowledge sits with its format.
//

import CoreGraphics
import Foundation

enum SonyRawFormat: RawFormat {
    nonisolated static let extensions: Set<String> = ["arw"]
    // nonisolated static let displayName: String = "Sony ARW"

    nonisolated static func extractThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) async throws -> CGImage {
        try await SonyThumbnailExtractor.extractSonyThumbnail(
            from: url,
            maxDimension: maxDimension,
            qualityCost: qualityCost,
        )
    }

    nonisolated static func extractFullJPEG(from url: URL, fullSize: Bool) async -> CGImage? {
        await JPGSonyARWExtractor.jpgSonyARWExtractor(from: url, fullSize: fullSize)
    }

    nonisolated static func focusLocation(from url: URL) -> String? {
        SonyMakerNoteParser.focusLocation(from: url)
    }

    /// TIFF Compression tag values used by Sony RAW. Newer bodies (A1, A7R V…)
    /// write 6/7; older bodies (A7R III and earlier) write 32767/32770.
    nonisolated static func rawFileTypeString(compressionCode: Int) -> String {
        switch compressionCode {
        case 1: "Uncompressed"
        case 6: "Compressed"
        case 7: "Lossless Compressed"
        case 32767: "Compressed"
        case 32770: "Lossless Compressed"
        default: "Unknown (\(compressionCode))"
        }
    }

    /// Per-body MP thresholds for L / M / S classification.
    nonisolated static func sizeClassThresholds(camera: String) -> (L: Double, M: Double) {
        let upper = camera.uppercased()
        if upper.contains("ILCE-7RM") { return (50, 22) } // A7R IV/V: 61/26/15 MP
        if upper.contains("ILCE-1") { return (40, 18) } // A1/A1 II: 50/21/12 MP
        if upper.contains("ILCE-9") { return (20, 10) } // A9 III: 24/12/6 MP
        if upper.contains("ILCE-7") { return (28, 14) } // A7M5: 33/17/9 MP
        return (25, 10) // generic fallback
    }
}
