import CoreGraphics
import Foundation
import PhotoAIContracts

public struct SubjectMaskInventoryEntry: Equatable, Sendable {
    public let hasMask: Bool
    public let confidence: Float
    public let geometry: SubjectMaskGeometry
    public let quality: SubjectMaskQuality

    public init(
        hasMask: Bool,
        confidence: Float,
        geometry: SubjectMaskGeometry,
        quality: SubjectMaskQuality
    ) {
        self.hasMask = hasMask
        self.confidence = confidence
        self.geometry = geometry
        self.quality = quality
    }

    public init(
        mask: CGImage,
        confidence: Float,
        sourceModificationDate: Date? = nil,
        cacheModificationDate: Date? = nil
    ) {
        let geometry = SubjectMaskGeometry.measure(
            mask: mask,
            sourceModificationDate: sourceModificationDate,
            cacheModificationDate: cacheModificationDate
        )
        self.init(
            hasMask: true,
            confidence: confidence,
            geometry: geometry,
            quality: SubjectMaskQuality(geometry: geometry)
        )
    }

    public static let absent: SubjectMaskInventoryEntry = {
        let geometry = SubjectMaskGeometry(
            coverage: 0,
            boundingBox: .zero,
            centroid: CGPoint(x: 0.5, y: 0.5),
            isFresh: false
        )
        return SubjectMaskInventoryEntry(
            hasMask: false,
            confidence: 0,
            geometry: geometry,
            quality: SubjectMaskQuality(geometry: geometry)
        )
    }()
}

/// Incrementally scans cached masks for package-owned image sources. It does
/// not invoke inference and publishes no UI state.
public actor SubjectMaskCatalogIndex {
    public private(set) var inventory: [UUID: SubjectMaskInventoryEntry] = [:]
    private var buildTask: Task<Void, Never>?

    public init() {}

    public func startBuild(
        sources: [AIImageSource],
        repository: SubjectMaskRepository,
        cacheMetadata: (any SubjectMaskCacheMetadataProviding)? = nil,
        batchSize: Int = 20,
        onUpdate: (@Sendable ([UUID: SubjectMaskInventoryEntry]) async -> Void)? = nil
    ) {
        buildTask?.cancel()
        inventory = [:]
        let boundedBatchSize = max(1, batchSize)
        buildTask = Task(priority: .utility) { [weak self] in
            await self?.runBuild(
                sources: sources,
                repository: repository,
                cacheMetadata: cacheMetadata,
                batchSize: boundedBatchSize,
                onUpdate: onUpdate
            )
        }
    }

    public func cancel() {
        buildTask?.cancel()
        buildTask = nil
    }

    public func waitForCurrentBuild() async {
        await buildTask?.value
    }

    private func runBuild(
        sources: [AIImageSource],
        repository: SubjectMaskRepository,
        cacheMetadata: (any SubjectMaskCacheMetadataProviding)?,
        batchSize: Int,
        onUpdate: (@Sendable ([UUID: SubjectMaskInventoryEntry]) async -> Void)?
    ) async {
        var batch: [UUID: SubjectMaskInventoryEntry] = [:]
        batch.reserveCapacity(batchSize)

        for source in sources {
            guard !Task.isCancelled else { return }
            let entry = await entry(
                for: source,
                repository: repository,
                cacheMetadata: cacheMetadata
            )
            batch[source.id] = entry
            if batch.count >= batchSize {
                await publish(batch, onUpdate: onUpdate)
                batch.removeAll(keepingCapacity: true)
            }
        }

        guard !Task.isCancelled else { return }
        if !batch.isEmpty {
            await publish(batch, onUpdate: onUpdate)
        }
        buildTask = nil
    }

    private func publish(
        _ batch: [UUID: SubjectMaskInventoryEntry],
        onUpdate: (@Sendable ([UUID: SubjectMaskInventoryEntry]) async -> Void)?
    ) async {
        inventory.merge(batch) { _, new in new }
        await onUpdate?(batch)
    }

    private func entry(
        for source: AIImageSource,
        repository: SubjectMaskRepository,
        cacheMetadata: (any SubjectMaskCacheMetadataProviding)?
    ) async -> SubjectMaskInventoryEntry {
        guard let result = await repository.cachedMask(for: source) else {
            return .absent
        }
        let key = await repository.storageKey(for: source)
        let metadata = await cacheMetadata?.cacheMetadata(for: key)
        let sourceIdentity = SourceFileIdentity.read(from: source.url)
        return SubjectMaskInventoryEntry(
            mask: result.mask,
            confidence: result.confidence,
            sourceModificationDate: sourceIdentity.modificationDate,
            cacheModificationDate: metadata?.modificationDate
        )
    }
}
