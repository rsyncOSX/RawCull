import PhotoAnalysisKit
import PhotoEvidenceContracts
import PhotoEvidenceEngine
import SwiftUI

private nonisolated struct BurstDetectedFace: Identifiable, Sendable {
    let evidence: DetectedFaceCloseUp
    let crop: CGImage
    var id: Int {
        evidence.id
    }
}

private actor BurstDetectedFaceLoader {
    static let shared = BurstDetectedFaceLoader()
    private let analyzer = FaceEvidenceAnalyzer()
    private let cache = FaceEvidenceCache()
    private let previewMaximumDimension = 1600
    private let previewPipelineVersion = 1

    func load(_ url: URL) async throws -> [BurstDetectedFace] {
        let access = await RawCullCatalogAccess.shared.retainAccess(for: [url])
        defer { withExtendedLifetime(access) {} }
        try Task.checkCancellation()
        let revision = BurstCloseUpIdentity.revision(url)
        let request = ReviewSourceRequest(url: url, preference: .highQualityPreview,
                                          policy: .appearance, embeddedPreviewMaximumDimension: previewMaximumDimension)
        guard let preview = try ReviewEmbeddedPreviewLoader().load(request)?.image else {
            throw CloseUpRenderError.unavailable
        }

        let signature = FaceEvidenceCache.Signature(
            sourceRevision: revision,
            previewMaximumDimension: previewMaximumDimension,
            previewPipelineVersion: previewPipelineVersion,
            algorithmVersion: FaceEvidenceAnalyzer.algorithmVersion,
            detectorRevision: FaceEvidenceAnalyzer.detectorRevision,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
        )
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
            try? cache.save(result, for: url, signature: signature)
        }
        return result.faces.compactMap { face in
            let target = DetectedFaceCloseUp(id: face.id, normalizedBounds: face.normalizedBounds,
                                             localDetail: face.localDetail)
            guard let crop = DetectedFaceRasterizer.crop(target, from: preview) else { return nil }
            return BurstDetectedFace(evidence: target, crop: crop)
        }
    }
}

struct BurstDetectedFacesView: View {
    let url: URL

    private enum State {
        case loading
        case loaded([BurstDetectedFace])
        case unavailable
    }

    @State private var state = State.loading
    @State private var retry = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Detected faces · embedded preview").font(.caption.weight(.semibold))
            switch state {
            case .loading:
                ProgressView().controlSize(.small).accessibilityLabel("Detecting faces")

            case let .loaded(faces) where faces.isEmpty:
                Text("No faces detected").font(.caption).foregroundStyle(.secondary)

            case let .loaded(faces):
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(faces) { face in
                            faceTile(face)
                        }
                    }
                }

            case .unavailable:
                HStack {
                    Text("Face close-ups unavailable").font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { retry += 1 }.controlSize(.small)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: retry) {
            state = .loading
            do {
                try await Task.sleep(for: .milliseconds(150))
                let faces = try await BurstDetectedFaceLoader.shared.load(url)
                try Task.checkCancellation()
                state = .loaded(faces)
            } catch {
                guard !Task.isCancelled else { return }
                state = .unavailable
            }
        }
    }

    private func faceTile(_ face: BurstDetectedFace) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Image(decorative: face.crop, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(width: 118, height: 92)
                .background(.black)
                .accessibilityLabel("Detected face \(face.id + 1)")
            if let detail = face.evidence.localDetail {
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
