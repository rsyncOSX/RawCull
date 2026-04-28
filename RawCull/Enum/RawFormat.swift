//
//  RawFormat.swift
//  RawCull
//
//  Describes per-vendor knowledge: which file extensions belong to the format,
//  how to extract an embedded thumbnail / full JPEG, how to read the AF focus
//  point, and how to render compression-code / size-class labels.
//
//  Conformers are enums (stateless, static-only). New brands are added by
//  writing a new conformer and listing it in `RawFormatRegistry.all`.
//

import CoreGraphics
import Foundation

protocol RawFormat: Sendable {
    /// Lowercased file extensions, no leading dot. e.g. `["arw"]`, `["nef"]`.
    nonisolated static var extensions: Set<String> { get }

    // Human-readable label for UI, e.g. "Sony ARW", "Nikon NEF".
    // nonisolated static var displayName: String { get }

    /// Embedded-JPEG-backed thumbnail. Must hop off the caller's thread internally.
    nonisolated static func extractThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) async throws -> CGImage

    /// Largest embedded JPEG, optionally downsampled. Returns nil when the format
    /// has no usable embedded preview or decode fails.
    nonisolated static func extractFullJPEG(from url: URL, fullSize: Bool) async -> CGImage?

    /// AF focus location encoded as `"imageWidth imageHeight focusX focusY"` in
    /// pixel space. Returns nil when the MakerNote lacks the tag or cannot be parsed.
    /// The string shape matches `ScanFiles.parseFocusNormalized`.
    nonisolated static func focusLocation(from url: URL) -> String?

    /// Human-readable label for a TIFF Compression tag value.
    nonisolated static func rawFileTypeString(compressionCode: Int) -> String

    /// Body-specific (L, M) megapixel thresholds for size-class classification.
    /// Return `(lThreshold, mThreshold)`; the caller labels S / M / L.
    nonisolated static func sizeClassThresholds(camera: String) -> (L: Double, M: Double)
}
