import Foundation

/// Immutable identity of the source bytes used to create a thumbnail.
///
/// Modification times are quantized to milliseconds. RawCull's scanners and
/// `URLResourceValues` therefore produce the same identity while still
/// detecting an in-place replacement at the precision used elsewhere by the
/// catalog and analysis caches.
nonisolated struct ThumbnailSourceFingerprint: Hashable, Sendable {
    static let currentCacheSchemaVersion = 3

    let standardizedPath: String
    let fileSize: Int64
    let modificationTimeMilliseconds: Int64
    let cacheSchemaVersion: Int

    init(
        url: URL,
        fileSize: Int64,
        modificationDate: Date,
        cacheSchemaVersion: Int = Self.currentCacheSchemaVersion,
    ) {
        standardizedPath = url.standardizedFileURL.path
        self.fileSize = fileSize
        modificationTimeMilliseconds = Int64(
            (modificationDate.timeIntervalSince1970 * 1_000).rounded(),
        )
        self.cacheSchemaVersion = cacheSchemaVersion
    }

    init(file: FileItem) {
        self.init(
            url: file.url,
            fileSize: file.size,
            modificationDate: file.dateModified,
        )
    }

    /// Reads source metadata once at a URL-only boundary. A metadata miss must
    /// bypass cache reuse instead of degrading to a stale path-only identity.
    static func readingMetadata(for url: URL) throws -> Self {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey,
            .contentModificationDateKey,
        ])
        guard let fileSize = values.fileSize,
              let modificationDate = values.contentModificationDate
        else {
            throw ThumbnailFingerprintError.metadataUnavailable
        }
        return Self(
            url: url,
            fileSize: Int64(fileSize),
            modificationDate: modificationDate,
        )
    }

    var deterministicComponent: String {
        "v\(cacheSchemaVersion)|p\(standardizedPath.utf8.count):\(standardizedPath)|s\(fileSize)|m\(modificationTimeMilliseconds)"
    }
}

nonisolated enum ThumbnailFingerprintError: Error, Equatable, Sendable {
    case metadataUnavailable
}

nonisolated enum ThumbnailPurpose: String, Hashable, Sendable {
    case grid
    case preview
}

nonisolated struct ThumbnailRepresentation: Hashable, Sendable {
    let purpose: ThumbnailPurpose
    let requestedMaxPixelSize: Int

    init(purpose: ThumbnailPurpose, requestedMaxPixelSize: Int) {
        self.purpose = purpose
        self.requestedMaxPixelSize = max(1, requestedMaxPixelSize)
    }

    /// A decoded artifact can only satisfy the same purpose and a request no
    /// larger than its actual decoded maximum dimension.
    func canSatisfy(
        request: ThumbnailRepresentation,
        decodedMaxPixelSize: Int,
    ) -> Bool {
        purpose == request.purpose
            && requestedMaxPixelSize >= request.requestedMaxPixelSize
            && decodedMaxPixelSize >= request.requestedMaxPixelSize
    }

    var deterministicComponent: String {
        "r\(purpose.rawValue)|x\(requestedMaxPixelSize)"
    }
}

nonisolated struct ThumbnailRequestKey: Hashable, Sendable {
    let source: ThumbnailSourceFingerprint
    let representation: ThumbnailRepresentation

    init(
        source: ThumbnailSourceFingerprint,
        purpose: ThumbnailPurpose,
        requestedMaxPixelSize: Int,
    ) {
        self.source = source
        representation = ThumbnailRepresentation(
            purpose: purpose,
            requestedMaxPixelSize: requestedMaxPixelSize,
        )
    }

    var deterministicComponent: String {
        "\(source.deterministicComponent):\(representation.deterministicComponent)"
    }
}

/// NSObject bridge required by NSCache. Equality and hashing use the immutable
/// value key, so independently-created wrappers address the same cache entry.
nonisolated final class ThumbnailRequestCacheKey: NSObject, @unchecked Sendable {
    let value: ThumbnailRequestKey

    init(_ value: ThumbnailRequestKey) {
        self.value = value
    }

    override var hash: Int { value.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
        (object as? ThumbnailRequestCacheKey)?.value == value
    }
}
