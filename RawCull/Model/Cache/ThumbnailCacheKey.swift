import Foundation

/// RawCull-owned identity for the source bytes used to render a thumbnail.
///
/// Thumbnail reuse is deliberately disabled when either piece of file-system
/// metadata is unavailable. A path alone cannot distinguish an image from a
/// replacement written at the same location.
nonisolated struct ThumbnailSourceFingerprint: Hashable, Sendable {
    let standardizedURL: URL
    let fileSize: Int64
    let modificationDate: Date

    var standardizedPath: String {
        standardizedURL.path
    }

    init?(
        sourceURL: URL,
        fileSize: Int64?,
        modificationDate: Date?,
    ) {
        guard sourceURL.isFileURL,
              let fileSize,
              fileSize >= 0,
              let modificationDate,
              modificationDate.timeIntervalSinceReferenceDate.isFinite
        else { return nil }

        standardizedURL = sourceURL.standardizedFileURL
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }

    static func resolve(for sourceURL: URL) -> Self? {
        guard sourceURL.isFileURL,
              let attributes = try? FileManager.default.attributesOfItem(
                  atPath: sourceURL.standardizedFileURL.path,
              )
        else { return nil }

        let fileSize = (attributes[.size] as? NSNumber)?.int64Value
        let modificationDate = attributes[.modificationDate] as? Date
        return Self(
            sourceURL: sourceURL,
            fileSize: fileSize,
            modificationDate: modificationDate,
        )
    }
}

/// Complete identity of one reusable thumbnail representation.
///
/// This type intentionally does not reuse PhotoAIKit's source fingerprint or
/// artifact keys. Thumbnail schema changes must never invalidate Vision, CLIP,
/// or subject-mask artifacts.
nonisolated struct ThumbnailCacheKey: Hashable, Sendable {
    static let schemaVersion = "v3-source-representation-thumbnails"

    enum Purpose: String, Hashable, Sendable {
        case grid
        case preview
    }

    enum OrientationPolicy: String, Hashable, Sendable {
        case sourceNormalized
    }

    let source: ThumbnailSourceFingerprint
    let purpose: Purpose
    let requestedPixelSize: Int
    let orientationPolicy: OrientationPolicy

    init?(
        sourceURL: URL,
        fileSize: Int64?,
        modificationDate: Date?,
        purpose: Purpose,
        requestedPixelSize: Int,
        orientationPolicy: OrientationPolicy = .sourceNormalized,
    ) {
        guard requestedPixelSize > 0,
              let source = ThumbnailSourceFingerprint(
                  sourceURL: sourceURL,
                  fileSize: fileSize,
                  modificationDate: modificationDate,
              )
        else { return nil }

        self.source = source
        self.purpose = purpose
        self.requestedPixelSize = requestedPixelSize
        self.orientationPolicy = orientationPolicy
    }

    static func resolve(
        for sourceURL: URL,
        purpose: Purpose,
        requestedPixelSize: Int,
        orientationPolicy: OrientationPolicy = .sourceNormalized,
    ) -> Self? {
        guard requestedPixelSize > 0,
              let source = ThumbnailSourceFingerprint.resolve(for: sourceURL)
        else { return nil }

        return Self(
            source: source,
            purpose: purpose,
            requestedPixelSize: requestedPixelSize,
            orientationPolicy: orientationPolicy,
        )
    }

    private init(
        source: ThumbnailSourceFingerprint,
        purpose: Purpose,
        requestedPixelSize: Int,
        orientationPolicy: OrientationPolicy,
    ) {
        self.source = source
        self.purpose = purpose
        self.requestedPixelSize = requestedPixelSize
        self.orientationPolicy = orientationPolicy
    }

    var standardizedSourceURL: URL {
        source.standardizedURL
    }

    func representation(
        purpose: Purpose,
        requestedPixelSize: Int,
        orientationPolicy: OrientationPolicy = .sourceNormalized,
    ) -> Self? {
        guard requestedPixelSize > 0 else { return nil }
        return Self(
            source: source,
            purpose: purpose,
            requestedPixelSize: requestedPixelSize,
            orientationPolicy: orientationPolicy,
        )
    }

    /// Stable, locale-independent input for memory and disk cache keys.
    var cacheIdentifier: String {
        let path = source.standardizedPath
        let modificationBits = source.modificationDate.timeIntervalSinceReferenceDate.bitPattern
        return [
            Self.schemaVersion,
            "path-bytes=\(path.utf8.count):\(path)",
            "source-size=\(source.fileSize)",
            "source-modification-bits=\(modificationBits)",
            "purpose=\(purpose.rawValue)",
            "requested-pixels=\(requestedPixelSize)",
            "orientation=\(orientationPolicy.rawValue)"
        ].joined(separator: "|")
    }

    var memoryCacheKey: NSString {
        cacheIdentifier as NSString
    }
}
