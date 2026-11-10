import OSLog
import PhotoAnalysisKit
import PhotoEvidenceContracts
import PhotoEvidenceEngine
import SwiftUI

private nonisolated struct BurstDetectedCrop: Identifiable, Sendable {
    let evidence: DetectedFaceCloseUp
    let animalKind: AnimalCloseUpDetector.Kind?
    let crop: CGImage
    var id: Int {
        evidence.id
    }
}

private actor BurstDetectedFaceLoader {
    static let shared = BurstDetectedFaceLoader()
    private let analyzer = FaceEvidenceAnalyzer()
    private let cache = FaceEvidenceCache()

    func load(_ url: URL) async throws -> (faces: [BurstDetectedCrop], animals: [BurstDetectedCrop]?) {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        let revision = BurstCloseUpIdentity.revision(url)
        let request = ReviewSourceRequest(url: url, preference: .highQualityPreview,
                                          policy: .appearance, embeddedPreviewMaximumDimension: FaceEvidenceCache.previewMaximumDimension)
        guard let preview = try ReviewEmbeddedPreviewLoader().load(request)?.image else {
            throw CloseUpRenderError.unavailable
        }

        let signature = FaceEvidenceCache.signature(sourceRevision: revision)
        let cached = cache.load(for: url, signature: signature, width: preview.width, height: preview.height)
        let result: FaceEvidenceResult = if let cached {
            cached
        } else {
            try await analyzer.analyze(preview)
        }
        try Task.checkCancellation()
        guard BurstCloseUpIdentity.revision(url) == revision else {
            throw CloseUpRenderError.sourceChanged
        }
        if cached == nil {
            do {
                try cache.save(result, for: url, signature: signature)
            } catch {
                Logger.process.debugMessageOnly("FaceEvidenceCache: WRITE FAILED")
            }
        }
        let animalRegions = try? AnimalCloseUpDetector.regions(in: preview)
        try Task.checkCancellation()
        guard BurstCloseUpIdentity.revision(url) == revision else {
            throw CloseUpRenderError.sourceChanged
        }
        let faces: [BurstDetectedCrop] = result.faces.compactMap { face in
            let target = DetectedFaceCloseUp(id: face.id, normalizedBounds: face.normalizedBounds,
                                             localDetail: face.localDetail)
            guard let crop = DetectedFaceRasterizer.crop(target, from: preview) else { return nil }
            return BurstDetectedCrop(evidence: target, animalKind: nil, crop: crop)
        }
        let animals: [BurstDetectedCrop]? = animalRegions.map { regions in
            regions.enumerated().compactMap { index, region in
                let target = DetectedFaceCloseUp(id: index, normalizedBounds: region.bounds, localDetail: nil)
                guard let crop = DetectedFaceRasterizer.crop(target, from: preview) else { return nil }
                return BurstDetectedCrop(evidence: target, animalKind: region.kind, crop: crop)
            }
        }
        return (faces, animals)
    }
}

struct BurstDetectedFacesView: View {
    let url: URL

    private enum State {
        case loading
        case loaded(faces: [BurstDetectedCrop], animals: [BurstDetectedCrop]?)
        case unavailable
    }

    @State private var state = State.loading
    @State private var retry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                ProgressView().controlSize(.small).accessibilityLabel("Detecting faces and animal landmarks")

            case let .loaded(faces, animals):
                if faces.isEmpty && animals?.isEmpty == true {
                    Text("No faces or animal landmarks detected").font(.caption).foregroundStyle(.secondary)
                } else if !faces.isEmpty || animals?.isEmpty == false {
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 8) {
                            ForEach(faces) { face in
                                cropTile(face)
                            }
                            ForEach(animals ?? []) { animal in
                                cropTile(animal)
                            }
                        }
                    }
                }
                if animals == nil {
                    HStack {
                        Text("Animal close-ups unavailable").font(.caption).foregroundStyle(.secondary)
                        Button("Retry") { retry += 1 }.controlSize(.small)
                    }
                }

            case .unavailable:
                HStack {
                    Text("Detected close-ups unavailable").font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { retry += 1 }.controlSize(.small)
                }
            }
        }
        .task(id: retry) {
            state = .loading
            do {
                try await Task.sleep(for: .milliseconds(150))
                let detections = try await BurstDetectedFaceLoader.shared.load(url)
                try Task.checkCancellation()
                state = .loaded(faces: detections.faces, animals: detections.animals)
            } catch {
                guard !Task.isCancelled else { return }
                state = .unavailable
            }
        }
    }

    private func cropTile(_ face: BurstDetectedCrop) -> some View {
        let label: LocalizedStringResource = switch face.animalKind {
        case .head: "Animal head"
        case .eye: "Animal eye"
        case nil: "Detected face \(face.id + 1)"
        }
        return VStack(alignment: .leading, spacing: 3) {
            Image(decorative: face.crop, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 92)
                .background(.black)
                .accessibilityLabel(Text(label))
            if face.animalKind != nil {
                Text(label)
            } else if let detail = face.evidence.localDetail {
                Text("Detail: \(detail.formatted(.number.precision(.significantDigits(3))))")
                    .help("Preview detail measurement for comparing similar captures of the same face.")
            } else {
                Text("Detail unavailable")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
