import CoreGraphics
import Foundation
import PhotoAIContracts

/// Reusable SAM3 orchestration: preprocessing, cache lookup/persistence, and batching.
/// Selection staleness remains a host-application concern.
public actor SegmentationService {
    private let provider: any SubjectSegmenting
    private let stores: [any SubjectMaskStoring]
    private let maxSide: Int

    public init(
        provider: any SubjectSegmenting,
        stores: [any SubjectMaskStoring] = [],
        maxSide: Int = 4_320
    ) {
        self.provider = provider
        self.stores = stores
        self.maxSide = maxSide
    }

    public func partitionByValidCache(
        sources: [AIImageSource],
        prompt: SubjectSegmentationPrompt
    ) async throws -> (cached: [AIImageSource], missing: [AIImageSource]) {
        var cached: [AIImageSource] = []
        var missing: [AIImageSource] = []
        for source in sources {
            try Task.checkCancellation()
            let key = await storageKey(source: source, prompt: prompt)
            var found = false
            for store in stores where await store.contains(key) {
                found = true
                break
            }
            if found {
                cached.append(source)
            } else {
                missing.append(source)
            }
        }
        return (cached, missing)
    }

    public func segment(
        image: CGImage,
        source: AIImageSource,
        prompt: SubjectSegmentationPrompt
    ) async throws -> SubjectSegmentationResult {
        let key = await storageKey(source: source, prompt: prompt)
        for store in stores {
            if let cached = await store.load(for: key) { return cached }
        }
        try Task.checkCancellation()

        guard let boundedImage = Self.boundedImage(image, maxSide: maxSide) else {
            throw SubjectSegmentationError.decodeFailure
        }
        let request = SubjectSegmentationRequest(
            sourceID: source.id,
            prompt: prompt,
            image: boundedImage,
            inputSize: CGSize(width: boundedImage.width, height: boundedImage.height),
            outputSize: CGSize(width: image.width, height: image.height),
            maxSide: maxSide
        )
        let result = try await provider.segment(request)
        try Task.checkCancellation()

        let displayMask = Self.resizedImage(result.mask, width: image.width, height: image.height)
            ?? result.mask
        let displaySize = CGSize(width: displayMask.width, height: displayMask.height)
        let displayResult = SubjectSegmentationResult(
            sourceID: result.sourceID,
            requestID: result.requestID,
            prompt: result.prompt,
            mask: displayMask,
            confidence: result.confidence,
            modelIdentity: result.modelIdentity,
            inputSize: result.inputSize,
            outputSize: displaySize,
            timing: result.timing,
            diagnostics: SubjectSegmentationDiagnostics(
                modelIdentity: result.diagnostics.modelIdentity,
                prompt: result.diagnostics.prompt,
                confidence: result.diagnostics.confidence,
                timing: result.diagnostics.timing,
                inputSize: result.diagnostics.inputSize,
                outputSize: displaySize,
                resourceName: result.diagnostics.resourceName,
                assetName: result.diagnostics.assetName
            )
        )
        for store in stores { try? await store.save(displayResult, for: key) }
        return displayResult
    }

    public func prefetch(
        sources: [AIImageSource],
        prompt: SubjectSegmentationPrompt,
        decoder: any ImageDecoding,
        progress: (@Sendable (SubjectMaskPrefetchProgress) async -> Void)? = nil
    ) async throws {
        let total = sources.count
        var completed = 0
        var cached = 0
        var generated = 0
        var failed = 0

        await progress?(SubjectMaskPrefetchProgress(
            completed: 0,
            total: total,
            cached: 0,
            generated: 0,
            failed: 0,
            currentSourceID: sources.first?.id
        ))

        for source in sources {
            try Task.checkCancellation()
            let key = await storageKey(source: source, prompt: prompt)
            var isCached = false
            for store in stores where await store.contains(key) {
                isCached = true
                break
            }
            if isCached {
                cached += 1
            } else {
                do {
                    let image = try await decoder.image(for: source)
                    _ = try await segment(image: image, source: source, prompt: prompt)
                    generated += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as SubjectSegmentationError where error == .cancelled {
                    throw CancellationError()
                } catch {
                    failed += 1
                }
            }
            completed += 1
            await progress?(SubjectMaskPrefetchProgress(
                completed: completed,
                total: total,
                cached: cached,
                generated: generated,
                failed: failed,
                currentSourceID: source.id
            ))
        }
    }

    private func storageKey(
        source: AIImageSource,
        prompt: SubjectSegmentationPrompt
    ) async -> SubjectMaskStorageKey {
        let identity = await Task { @concurrent in
            SourceFileIdentity.read(from: source.url)
        }.value
        return SubjectMaskStorageKey(
            source: source,
            sourceIdentity: identity,
            prompt: prompt,
            modelIdentity: provider.modelIdentity,
            inputMaxSide: maxSide
        )
    }

    private nonisolated static func boundedImage(_ image: CGImage, maxSide: Int) -> CGImage? {
        let longestSide = max(image.width, image.height)
        guard longestSide > maxSide else { return image }
        let scale = CGFloat(maxSide) / CGFloat(longestSide)
        return resizedImage(
            image,
            width: max(1, Int(CGFloat(image.width) * scale)),
            height: max(1, Int(CGFloat(image.height) * scale))
        )
    }

    private nonisolated static func resizedImage(
        _ image: CGImage,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard image.width != width || image.height != height else { return image }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
