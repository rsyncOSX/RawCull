import CoreImage
import Foundation

/// Display pixels are completed on this actor, never lazily on SwiftUI's drawing thread.
/// JPEG export and the persistent JPEG cache remain independent of these previews.
actor RAWPreviewRenderer {
    static let shared = RAWPreviewRenderer(cacheByteLimit: 256 * 1024 * 1024)

    nonisolated struct Preview: Sendable {
        let image: CGImage
        let nativeSize: CGSize
    }

    private var context: CIContext?
    private var filter: CIRAWFilter?
    private var sourceKey: RAWPreviewCache.Key?
    private var nativeSize: CGSize = .zero
    private var cache: RAWPreviewCache

    init(cacheByteLimit: Int = 0) {
        cache = RAWPreviewCache(byteLimit: cacheByteLimit)
    }

    func clearCache() {
        cache.removeAll()
        releaseSource()
    }

    func cachedPreview(for key: RAWPreviewCache.Key) throws -> Preview? {
        try Task.checkCancellation()
        return cache.preview(for: key)
    }

    func releaseSource() {
        filter = nil
        sourceKey = nil
        nativeSize = .zero
        context?.clearCaches()
        context = nil
    }

    func render(url: URL, maximumDimension: Int? = nil, inspectionExposureEV: Double? = nil) throws -> Preview {
        try Task.checkCancellation()
        return try autoreleasepool {
            let key = try RAWPreviewCache.Key(
                url: url,
                maximumDimension: maximumDimension,
                inspectionExposureEV: inspectionExposureEV,
            )
            if let preview = cache.preview(for: key) {
                return preview
            }
            // Completed previews have a bounded cache; retaining the full RAW graph as
            // well is costly for native-resolution images and slows source changes.
            let context = self.context ?? CIContext(options: [.cacheIntermediates: false, .workingFormat: CIFormat.RGBAh])
            self.context = context
            let filter = try rawFilter(for: key, context: context)
            let scale = Self.previewScale(nativeSize: self.nativeSize, maximumDimension: maximumDimension)
            filter.scaleFactor = scale
            if let inspectionExposureEV {
                filter.exposure = Float(inspectionExposureEV)
                filter.boostShadowAmount = 2
                if #available(macOS 26.0, *), filter.isHighlightRecoverySupported {
                    filter.isHighlightRecoveryEnabled = true
                }
            }
            guard var output = filter.outputImage,
                  !output.extent.isEmpty, !output.extent.isInfinite, !output.extent.isNull
            else { throw RenderError.decodingFailed }
            // CIRAWFilter already applies EXIF orientation. Derive upright native geometry
            // from its output so portrait files are not rotated or transposed a second time.
            let sensorSize = self.nativeSize
            let sameOrientation = (output.extent.width >= output.extent.height) == (sensorSize.width >= sensorSize.height)
            let displayNativeSize = sameOrientation ? sensorSize : CGSize(width: sensorSize.height, height: sensorSize.width)
            if inspectionExposureEV != nil {
                output = output.applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 0.25, "inputShadowAmount": 0.0,
                ])
            }
            try Task.checkCancellation()
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let image = context.createCGImage(
                      output,
                      from: output.extent,
                      format: .RGBA8,
                      colorSpace: colorSpace,
                      deferred: false,
                  )
            else { throw RenderError.decodingFailed }
            try Task.checkCancellation()
            let preview = Preview(image: image, nativeSize: displayNativeSize)
            cache.insert(preview, for: key)
            return preview
        }
    }

    private func rawFilter(for key: RAWPreviewCache.Key, context: CIContext) throws -> CIRAWFilter {
        // Recreate when changing source/revision or entering/leaving inspection. Camera
        // defaults must not inherit inspection's highlight recovery or shadow boost.
        let sameSource = sourceKey?.url == key.url && sourceKey?.fileSize == key.fileSize
            && sourceKey?.modificationDate == key.modificationDate
        let sameMode = (sourceKey?.inspectionExposureEV != nil) == (key.inspectionExposureEV != nil)
        if sameSource, sameMode, let filter {
            return filter
        }
        filter = nil
        sourceKey = nil
        context.clearCaches()
        guard let loaded = CIRAWFilter(imageURL: key.url) else { throw RenderError.decodingFailed }
        // Preserve system-decoder fallback for files without RAW 9 support.
        if loaded.supportedDecoderVersions.contains(.version9) {
            loaded.decoderVersion = .version9
        } else if loaded.supportedDecoderVersions.contains(.version9DNG) {
            loaded.decoderVersion = .version9DNG
        }
        // CIRAWFilter.nativeSize can change after scaleFactor is set. Capture the
        // original dimensions once so resizes and native geometry remain stable.
        nativeSize = loaded.nativeSize
        filter = loaded
        sourceKey = key
        return loaded
    }

    nonisolated static func previewScale(nativeSize: CGSize, maximumDimension: Int?) -> Float {
        let longest = max(nativeSize.width, nativeSize.height)
        guard let maximumDimension, maximumDimension > 0, longest.isFinite, longest > 0 else { return 1 }
        return Float(min(1, CGFloat(maximumDimension) / longest))
    }

    nonisolated enum RenderError: Error { case decodingFailed }
}

/// Lossless LRU cache, owned by the renderer. Fit/native and inspection pixels have separate keys.
nonisolated struct RAWPreviewCache {
    struct Key: Equatable, Sendable {
        let url: URL
        let fileSize: Int
        let modificationDate: Date
        let maximumDimension: Int?
        let inspectionExposureEV: Double?

        init(url: URL, maximumDimension: Int?, inspectionExposureEV: Double?) throws {
            self.url = url.standardizedFileURL
            let values = try self.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let fileSize = values.fileSize, let date = values.contentModificationDate else {
                throw CocoaError(.fileReadUnknown)
            }
            self.fileSize = fileSize
            modificationDate = date
            self.maximumDimension = maximumDimension
            self.inspectionExposureEV = inspectionExposureEV
        }
    }

    private struct Entry {
        let key: Key
        let preview: RAWPreviewRenderer.Preview
        var cost: Int {
            preview.image.bytesPerRow * preview.image.height
        }
    }

    let byteLimit: Int
    private(set) var byteCount = 0
    private var entries: [Entry] = []

    mutating func preview(for key: Key) -> RAWPreviewRenderer.Preview? {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return nil }
        let entry = entries.remove(at: index)
        entries.append(entry)
        return entry.preview
    }

    mutating func insert(_ preview: RAWPreviewRenderer.Preview, for key: Key) {
        let entry = Entry(key: key, preview: preview)
        // Drop obsolete revisions and exposure values, but retain fit/native variants.
        for index in entries.indices.reversed() where entries[index].key.url == key.url {
            let old = entries[index].key
            if old.fileSize != key.fileSize || old.modificationDate != key.modificationDate
                || (old.maximumDimension == key.maximumDimension
                    && (old.inspectionExposureEV != nil) == (key.inspectionExposureEV != nil))
            {
                byteCount -= entries.remove(at: index).cost
            }
        }
        guard entry.cost <= byteLimit else { return }
        while byteCount + entry.cost > byteLimit, !entries.isEmpty {
            byteCount -= entries.removeFirst().cost
        }
        entries.append(entry)
        byteCount += entry.cost
    }

    mutating func removeAll() {
        entries.removeAll()
        byteCount = 0
    }
}

nonisolated enum RAWPreviewSizing {
    static func fitDimension(viewport: CGSize, displayScale: CGFloat) -> Int? {
        guard viewport.width.isFinite, viewport.height.isFinite, displayScale.isFinite,
              viewport.width > 0, viewport.height > 0, displayScale > 0 else { return nil }
        let pixels = ceil(max(viewport.width, viewport.height) * displayScale / 256) * 256
        guard pixels.isFinite, pixels < CGFloat(Int.max) else { return nil }
        return max(256, Int(pixels))
    }
}
