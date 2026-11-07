import CoreImage
import CryptoKit
import ImageIO
import PhotoEvidenceContracts
import PhotoEvidenceEngine
import PhotoEvidenceUI
import SwiftUI

/// Inspection choices are preferences, separate from ratings and burst decisions.
@MainActor final class BurstCloseUpRegionStore: CloseUpRegionStoring {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(for frame: CloseUpFrame) throws -> CloseUpRegionRecord? {
        guard let data = defaults.data(forKey: key(frame.id)) else { return nil }
        return try JSONDecoder().decode(CloseUpRegionRecord.self, from: data)
    }

    func save(_ record: CloseUpRegionRecord) throws {
        try defaults.set(JSONEncoder().encode(record), forKey: key(record.sourceID))
    }

    private func key(_ url: URL) -> String {
        "PhotoEvidenceKit.ManualRegion.v1." + SHA256.hash(data: Data(url.standardizedFileURL.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

nonisolated enum BurstCloseUpIdentity {
    static func revision(_ url: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let inode = (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        return "\(url.standardizedFileURL.absoluteString)|\(size)|\(modified)|\(inode)"
    }

    static func source(_ url: URL, raw: Bool) -> CloseUpRenderSource {
        CloseUpRenderSource(kind: raw ? .developedRAW : .embeddedPreview,
                            backendID: raw ? "RawCull.RAW9.fullSizeJPEG" : "RawCull.fullSizePreview",
                            revision: raw ? "raw9-default-jpeg-v1" : revision(FullSizePreviewLoader.sidecarJPEGURL(for: url)))
    }
}

/// Serializes native decoding across actor reentrancy; retains no decoded source cache.
actor BurstCloseUpRenderer: CloseUpRendering {
    private var tail: Task<CloseUpRender, Error>?
    private var tailID: UUID?
    func render(_ request: CloseUpRequest) async throws -> CloseUpRender {
        let previous = tail
        let id = UUID()
        let task = Task {
            _ = await previous?.result
            try Task.checkCancellation()
            return try await Self.makeRender(request)
        }
        tail = task
        tailID = id
        defer {
            if tailID == id {
                tail = nil; tailID = nil
            }
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }

    @concurrent private static func makeRender(_ request: CloseUpRequest) async throws -> CloseUpRender {
        let url = request.frame.id
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        let raw = request.renderSource.kind == .developedRAW
        guard BurstCloseUpIdentity.revision(url) == request.frame.revision,
              BurstCloseUpIdentity.source(url, raw: raw) == request.renderSource
        else {
            throw CloseUpRenderError.sourceChanged
        }
        let image: CGImage
        let label: String
        if raw {
            image = try await ZoomPreviewHandler.loadDevelopedRAWPreview(for: url)
            let supported = CIRAWFilter(imageURL: url)?.supportedDecoderVersions ?? []
            label = supported.contains(.version9) || supported.contains(.version9DNG)
                ? "RAW 9 decoded · full-size JPEG" : "RAW decoded · full-size JPEG"
        } else {
            guard let preview = await FullSizePreviewLoader.shared.loadEmbeddedPreview(for: url) else {
                throw CloseUpRenderError.unavailable
            }
            image = preview
            label = FileManager.default.fileExists(atPath: FullSizePreviewLoader.sidecarJPEGURL(for: url).path)
                ? "Sidecar JPG preview" : "Embedded preview"
        }
        try Task.checkCancellation()
        guard BurstCloseUpIdentity.revision(url) == request.frame.revision,
              BurstCloseUpIdentity.source(url, raw: raw) == request.renderSource
        else {
            throw CloseUpRenderError.sourceChanged
        }
        return try CloseUpRasterizer.render(image, request: request, sourceLabel: label)
    }
}

struct BurstCloseUpsView: View {
    let urls: [URL]
    let recordedAFPoints: [URL: CGPoint]
    let currentURL: URL?
    let raw: Bool
    let model: CloseUpModel
    let renderer: BurstCloseUpRenderer
    let activate: (URL) -> Void
    let onUseAFPoint: (URL) -> Void
    let onClose: () -> Void
    @State private var frames: [CloseUpFrame] = []
    @State private var sources: [URL: CloseUpRenderSource] = [:]

    @State private var orientations: [URL: UInt32] = [:]

    private var afPoints: [URL: CloseUpAFPointAvailability] {
        var all = frames
        if let reference = model.reference, !all.contains(where: { $0.id == reference.id }) { all.append(reference) }
        return Dictionary(uniqueKeysWithValues: all.map { frame in
            (frame.id, BurstCloseUpAFPoint.availability(frame: frame, point: recordedAFPoints[frame.id],
                                                       orientation: orientations[frame.id]))
        })
    }

    private struct Inputs: Hashable {
        let urls: [URL]
        let reference: URL?
        let raw: Bool
    }

    var body: some View {
        CloseUpPanel(frames: frames, currentFrameID: currentURL, model: model,
                     renderer: renderer, renderSources: sources, afPoints: afPoints,
                     onActivate: { frame in
                         guard urls.contains(frame.id) || model.reference?.id == frame.id else { return }
                         activate(frame.id)
                     }, onUseAFPoint: { frame in
                         onUseAFPoint(frame.id)
                     }, onClose: onClose)
            .task(id: Inputs(urls: urls, reference: model.reference?.id, raw: raw)) {
                let selected = urls
                var all = selected
                if let reference = model.reference, !all.contains(reference.id) {
                    all.append(reference.id)
                }
                let requestedURLs = all
                let loaded = await Task { @concurrent in
                    let access = await RawCullCatalogAccess.shared.retainAccess(for: requestedURLs)
                    defer { withExtendedLifetime(access) {} }
                    return requestedURLs.map { url in
                        let frame = CloseUpFrame(id: url, name: url.lastPathComponent, revision: BurstCloseUpIdentity.revision(url))
                        return (frame, BurstCloseUpAFPoint.orientation(for: url))
                    }
                }.value
                guard !Task.isCancelled else { return }
                orientations = Dictionary(uniqueKeysWithValues: loaded.compactMap { frame, orientation in
                    orientation.map { (frame.id, $0) }
                })
                let result = loaded.map { $0.0 }
                sources = Dictionary(uniqueKeysWithValues: result.map { ($0.id, BurstCloseUpIdentity.source($0.id, raw: raw)) })
                frames = result.filter { selected.contains($0.id) }
                if let reference = model.reference, let updated = result.first(where: { $0.id == reference.id }) {
                    model.updateReference(updated)
                }
            }
    }
}

/// Keeps close-up comparison selection separate from the active review frame.
enum BurstCloseUpSelection {
    static func select(
        _ url: URL, in urls: [URL], current: URL?, selection: Set<URL>,
        modifiers: NSEvent.ModifierFlags
    ) -> Set<URL> {
        guard urls.contains(url) else { return selection }
        if modifiers.contains(.shift), let current,
           let anchor = urls.firstIndex(of: current), let target = urls.firstIndex(of: url) {
            let range = Set(urls[min(anchor, target)...max(anchor, target)])
            return modifiers.contains(.command) ? selection.union(range) : range
        }
        if modifiers.contains(.command) {
            var result = selection
            if !result.insert(url).inserted { result.remove(url) }
            return result
        }
        return [url]
    }
}

/// Camera AF metadata uses sensor coordinates; crop regions use oriented coordinates.
nonisolated enum BurstCloseUpAFPoint {
    static func orientation(for url: URL) -> UInt32? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value
            ?? (tiff?[kCGImagePropertyTIFFOrientation] as? NSNumber)?.uint32Value ?? 1
    }

    static func availability(frame: CloseUpFrame, point: CGPoint?, orientation: UInt32?) -> CloseUpAFPointAvailability {
        guard let point else { return .unavailable(reason: "No usable recorded AF point is available.") }
        guard point.x.isFinite, point.y.isFinite, (0...1).contains(point.x), (0...1).contains(point.y) else {
            return .unavailable(reason: "Recorded AF coordinates are invalid.")
        }
        guard let orientation, (1...8).contains(orientation) else {
            return .unavailable(reason: "Image orientation is unavailable for AF placement.")
        }
        let x = point.x, y = point.y
        let center: CGPoint
        switch orientation {
        case 2: center = CGPoint(x: 1 - x, y: y)
        case 3: center = CGPoint(x: 1 - x, y: 1 - y)
        case 4: center = CGPoint(x: x, y: 1 - y)
        case 5: center = CGPoint(x: y, y: x)
        case 6: center = CGPoint(x: 1 - y, y: x)
        case 7: center = CGPoint(x: 1 - y, y: 1 - x)
        case 8: center = CGPoint(x: y, y: 1 - x)
        default: center = point
        }
        guard let target = CloseUpAFPoint(frame: frame, center: center) else {
            return .unavailable(reason: "Recorded AF coordinates are invalid.")
        }
        return .available(target)
    }
}
