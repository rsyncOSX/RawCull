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

private nonisolated enum BurstFaceStatus: Sendable {
    case ready
    case noFace
    case multipleFaces
    case detailUnavailable
}

private actor BurstDetectedFaceLoader {
    static let shared = BurstDetectedFaceLoader()
    private let analyzer = FaceEvidenceAnalyzer()
    private let cache = FaceEvidenceCache()
    private var nextFaceCachePrune = Date.distantPast

    private final class AnimalRegions {
        let values: [AnimalCloseUpDetector.Region]

        init(_ values: [AnimalCloseUpDetector.Region]) {
            self.values = values
        }
    }

    private let animalCache: NSCache<NSString, AnimalRegions> = {
        let cache = NSCache<NSString, AnimalRegions>()
        cache.countLimit = 64
        return cache
    }()

    func load(_ url: URL) async throws -> (faces: [BurstDetectedCrop], animals: [BurstDetectedCrop]?, status: BurstFaceStatus) {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        let now = Date.now
        if now >= nextFaceCachePrune {
            cache.pruneExpiredRecords(now: now)
            nextFaceCachePrune = now.addingTimeInterval(24 * 60 * 60)
        }
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
        let animalKey = "\(revision)|\(preview.width)x\(preview.height)" as NSString
        let cachedAnimals = animalCache.object(forKey: animalKey)
        let animalRegions = cachedAnimals?.values ?? (try? AnimalCloseUpDetector.regions(in: preview))
        try Task.checkCancellation()
        guard BurstCloseUpIdentity.revision(url) == revision else {
            throw CloseUpRenderError.sourceChanged
        }
        if cachedAnimals == nil, let animalRegions {
            animalCache.setObject(AnimalRegions(animalRegions), forKey: animalKey)
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
        let status: BurstFaceStatus
        switch result.faces.count {
        case 0:
            status = .noFace
        case 1:
            if let detail = result.faces.first?.localDetail, detail.isFinite, detail > 0 {
                status = .ready
            } else {
                status = .detailUnavailable
            }
        default:
            status = .multipleFaces
        }
        return (faces, animals, status)
    }
}

struct BurstDetectedFacesView: View {
    let url: URL

    private enum State {
        case loading
        case loaded(faces: [BurstDetectedCrop], animals: [BurstDetectedCrop]?, status: BurstFaceStatus)
        case unavailable
    }

    @State private var state = State.loading
    @State private var retry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch state {
            case .loading:
                Label("Checking…", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.yellow)

            case let .loaded(faces, animals, status):
                if !faces.isEmpty || animals?.isEmpty == false {
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
                faceStatusLabel(status)
                if animals == nil {
                    HStack {
                        Text("Animal close-ups unavailable").font(.caption).foregroundStyle(.secondary)
                        Button("Retry") { retry += 1 }.controlSize(.small)
                    }
                }

            case .unavailable:
                HStack {
                    Label("Face check unavailable", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
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
                state = .loaded(faces: detections.faces, animals: detections.animals, status: detections.status)
            } catch {
                guard !Task.isCancelled else { return }
                state = .unavailable
            }
        }
    }

    private func faceStatusLabel(_ status: BurstFaceStatus) -> some View {
        let title: LocalizedStringKey = switch status {
        case .ready: "Face ready"
        case .noFace: "No face detected"
        case .multipleFaces: "Multiple faces detected"
        case .detailUnavailable: "Face detail unavailable"
        }
        return Label(title, systemImage: status == .ready ? "checkmark.circle" : "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(status == .ready ? Color.green : Color.red)
            .help("Face evidence for this frame, measured from the embedded preview.")
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
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}
