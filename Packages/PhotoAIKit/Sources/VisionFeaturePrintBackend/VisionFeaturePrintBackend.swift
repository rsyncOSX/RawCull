import CoreGraphics
import Foundation
import PhotoAIContracts
import Vision

/// Typed opaque Vision feature-print backend. `VNFeaturePrintObservation` never
/// crosses this actor/module boundary; callers persist and compare artifacts.
public actor VisionFeaturePrintBackend:
    ImageSimilarityArtifactProviding,
    ImageSimilarityArtifactComparing
{
    public nonisolated let revision: Int
    public nonisolated let backendDescriptor: SimilarityBackendDescriptor

    public init(revision: Int = VNGenerateImageFeaturePrintRequestRevision2) {
        self.revision = revision
        self.backendDescriptor = SimilarityBackendDescriptor(
            backend: "vision-feature-print",
            modelFingerprint: "apple-vision-feature-print:revision-\(revision)",
            representation: "vnfeatureprint-keyed-archive-v1",
            preprocessingVersion: "vision-framework-managed-v1",
            normalizationVersion: "vision-feature-print-native-v1",
            configurationVersion: "request-revision-\(revision)"
        )
    }

    public func artifact(
        for image: CGImage,
        source: AIImageSource
    ) async throws -> SimilarityArtifact {
        try Task.checkCancellation()
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = revision
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw VisionFeaturePrintError.generationFailed(String(describing: error))
        }
        try Task.checkCancellation()
        guard let observation = request.results?.first as? VNFeaturePrintObservation else {
            throw VisionFeaturePrintError.missingObservation
        }
        let payload: Data
        do {
            payload = try NSKeyedArchiver.archivedData(
                withRootObject: observation,
                requiringSecureCoding: true
            )
        } catch {
            throw VisionFeaturePrintError.encodingFailed(String(describing: error))
        }
        return SimilarityArtifact(
            descriptor: SimilarityArtifactDescriptor(
                backend: backendDescriptor,
                dimensions: nil,
                sourceFingerprint: SourceFingerprint(source: source)
            ),
            payload: payload
        )
    }

    public nonisolated func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact
    ) throws -> Float? {
        guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
              left.descriptor.backend == backendDescriptor.backend,
              left.descriptor.modelFingerprint == backendDescriptor.modelFingerprint
        else { return nil }
        let leftObservation = try Self.decode(left.payload)
        let rightObservation = try Self.decode(right.payload)
        var distance: Float = 0
        do {
            try leftObservation.computeDistance(&distance, to: rightObservation)
        } catch {
            throw VisionFeaturePrintError.comparisonFailed(String(describing: error))
        }
        guard distance.isFinite else {
            throw VisionFeaturePrintError.comparisonFailed("Vision returned a non-finite distance.")
        }
        return distance
    }

    private nonisolated static func decode(
        _ data: Data
    ) throws -> VNFeaturePrintObservation {
        do {
            guard let observation = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: VNFeaturePrintObservation.self,
                from: data
            ) else { throw VisionFeaturePrintError.invalidPayload }
            return observation
        } catch let error as VisionFeaturePrintError {
            throw error
        } catch {
            throw VisionFeaturePrintError.decodingFailed(String(describing: error))
        }
    }
}

public enum VisionFeaturePrintError: Error, Equatable, Sendable {
    case generationFailed(String)
    case missingObservation
    case encodingFailed(String)
    case decodingFailed(String)
    case invalidPayload
    case comparisonFailed(String)
}
