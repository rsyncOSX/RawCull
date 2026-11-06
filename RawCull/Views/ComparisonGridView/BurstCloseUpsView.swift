import CoreImage
import CryptoKit
import SwiftUI
import PhotoEvidenceContracts
import PhotoEvidenceEngine
import PhotoEvidenceUI

/// Inspection choices are preferences, separate from ratings and burst decisions.
@MainActor final class BurstCloseUpRegionStore: CloseUpRegionStoring {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load(for frame: CloseUpFrame) throws -> CloseUpRegionRecord? {
        guard let data = defaults.data(forKey: key(frame.id)) else { return nil }
        return try JSONDecoder().decode(CloseUpRegionRecord.self, from: data)
    }
    func save(_ record: CloseUpRegionRecord) throws {
        defaults.set(try JSONEncoder().encode(record), forKey: key(record.sourceID))
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
        defer { if tailID == id { tail = nil; tailID = nil } }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    @concurrent private static func makeRender(_ request: CloseUpRequest) async throws -> CloseUpRender {
        let url = request.frame.id
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        let raw = request.renderSource.kind == .developedRAW
        guard BurstCloseUpIdentity.revision(url) == request.frame.revision,
              BurstCloseUpIdentity.source(url, raw: raw) == request.renderSource else {
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
              BurstCloseUpIdentity.source(url, raw: raw) == request.renderSource else {
            throw CloseUpRenderError.sourceChanged
        }
        return try CloseUpRasterizer.render(image, request: request, sourceLabel: label)
    }
}

struct BurstCloseUpsView: View {
    let urls: [URL]
    let currentURL: URL?
    let raw: Bool
    let model: CloseUpModel
    let renderer: BurstCloseUpRenderer
    let activate: (URL) -> Void
    let onClose: () -> Void
    @State private var frames: [CloseUpFrame] = []
    @State private var sources: [URL: CloseUpRenderSource] = [:]

    private struct Inputs: Hashable {
        let urls: [URL]
        let reference: URL?
        let raw: Bool
    }
    var body: some View {
        CloseUpPanel(frames: frames, currentFrameID: currentURL, model: model,
            renderer: renderer, renderSources: sources,
            onActivate: { frame in
                guard urls.contains(frame.id) else { return }
                activate(frame.id)
            }, onClose: onClose)
        .task(id: Inputs(urls: urls, reference: model.reference?.id, raw: raw)) {
            let selected = urls
            var all = selected
            if let reference = model.reference, !all.contains(reference.id) { all.append(reference.id) }
            let requestedURLs = all
            let result = await Task { @concurrent in
                let access = await RawCullCatalogAccess.shared.retainAccess(for: requestedURLs)
                defer { withExtendedLifetime(access) {} }
                return requestedURLs.map { CloseUpFrame(id: $0, name: $0.lastPathComponent, revision: BurstCloseUpIdentity.revision($0)) }
            }.value
            guard !Task.isCancelled else { return }
            sources = Dictionary(uniqueKeysWithValues: result.map { ($0.id, BurstCloseUpIdentity.source($0.id, raw: raw)) })
            frames = result.filter { selected.contains($0.id) }
            if let reference = model.reference, let updated = result.first(where: { $0.id == reference.id }) {
                model.updateReference(updated)
            }
        }
    }
}
