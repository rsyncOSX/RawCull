import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

actor SavedFilesRecorder {
    private var snapshots: [[SavedFiles]] = []
    private var waiters: [(
        count: Int,
        continuation: CheckedContinuation<[[SavedFiles]], Never>,
    )] = []

    func record(_ savedFiles: [SavedFiles]) {
        snapshots.append(savedFiles)
        let ready = waiters.filter { snapshots.count >= $0.count }
        waiters.removeAll { snapshots.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume(returning: snapshots)
        }
    }

    func waitForSnapshotCount(_ count: Int) async -> [[SavedFiles]] {
        if snapshots.count >= count {
            return snapshots
        }
        return await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }
}

actor FailingThenSuccessfulSave {
    private var attempts = 0
    private var savedSnapshots: [[SavedFiles]] = []

    func save(_ snapshot: [SavedFiles]) throws {
        attempts += 1
        if attempts == 1 {
            throw CocoaError(.fileWriteNoPermission)
        }
        savedSnapshots.append(snapshot)
    }

    func state() -> (attempts: Int, snapshots: [[SavedFiles]]) {
        (attempts, savedSnapshots)
    }
}

actor SharpnessScoreURLRecorder {
    private var fileNames: [String] = []

    func record(_ fileName: String) {
        fileNames.append(fileName)
    }

    func recordedFileNames() -> [String] {
        fileNames
    }
}

actor SimilarityEmbeddingCancellationProbe {
    private var startedCount = 0
    private var cancelledCount = 0

    func embedding() async -> Data? {
        startedCount += 1
        do {
            try await Task.sleep(for: .seconds(30))
            return Data([1])
        } catch is CancellationError {
            cancelledCount += 1
            return nil
        } catch {
            return nil
        }
    }

    func waitUntilStarted(_ count: Int) async {
        while startedCount < count {
            await Task.yield()
        }
    }

    func counts() -> (started: Int, cancelled: Int) {
        (startedCount, cancelledCount)
    }
}

nonisolated struct CancellationSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = similarityTestBackendDescriptor
    let probe: SimilarityEmbeddingCancellationProbe

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var iterator = sources.makeIterator()
        var artifacts: [UUID: SimilarityArtifact] = [:]
        var failures: [RawCullSimilarityIndexingFailure] = []
        var completed = 0

        await withTaskGroup(
            of: (AIImageSource, Data?).self,
        ) { group in
            for _ in 0 ..< min(4, sources.count) {
                guard let source = iterator.next() else { break }
                group.addTask {
                    await (source, probe.embedding())
                }
            }

            while let (source, payload) = await group.next() {
                completed += 1
                if let payload {
                    artifacts[source.id] = makeSimilarityTestArtifact(
                        source: source,
                        payload: payload,
                    )
                } else {
                    failures.append(
                        RawCullSimilarityIndexingFailure(
                            source: source,
                            message: "Cancelled",
                        ),
                    )
                }
                await progress?(
                    RawCullSimilarityIndexingProgress(
                        completed: completed,
                        total: sources.count,
                        currentSourceID: source.id,
                    ),
                )

                guard !Task.isCancelled,
                      let next = iterator.next()
                else { continue }
                group.addTask {
                    await (next, probe.embedding())
                }
            }
        }

        try Task.checkCancellation()
        return RawCullSimilarityIndexingOutput(
            artifacts: artifacts,
            failures: failures,
        )
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        similarityTestDistance(from: left, to: right)
    }
}

nonisolated struct ImmediateSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = similarityTestBackendDescriptor

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        for (offset, source) in sources.enumerated() {
            artifacts[source.id] = makeSimilarityTestArtifact(
                source: source,
                payload: Data([UInt8(offset + 1)]),
            )
            await progress?(
                RawCullSimilarityIndexingProgress(
                    completed: offset + 1,
                    total: sources.count,
                    currentSourceID: source.id,
                ),
            )
        }
        return RawCullSimilarityIndexingOutput(
            artifacts: artifacts,
            failures: [],
        )
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        similarityTestDistance(from: left, to: right)
    }
}

actor SimilarityEmbeddingSuspensionProbe {
    private var startedCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func suspendIgnoringCancellation() async -> Data? {
        startedCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
        return Data([1])
    }

    func waitUntilStarted(_ count: Int) async {
        while startedCount < count {
            await Task.yield()
        }
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}

nonisolated struct SuspendingSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = similarityTestBackendDescriptor
    let probe: SimilarityEmbeddingSuspensionProbe

    func index(
        sources: [AIImageSource],
        maxPixelSize _: Int,
        progress: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        var artifacts: [UUID: SimilarityArtifact] = [:]
        for (offset, source) in sources.enumerated() {
            let payload: Data = if source.url.lastPathComponent.hasPrefix("slow") {
                await probe.suspendIgnoringCancellation() ?? Data()
            } else {
                Data([2])
            }
            artifacts[source.id] = makeSimilarityTestArtifact(
                source: source,
                payload: payload,
            )
            await progress?(
                RawCullSimilarityIndexingProgress(
                    completed: offset + 1,
                    total: sources.count,
                    currentSourceID: source.id,
                ),
            )
        }
        return RawCullSimilarityIndexingOutput(artifacts: artifacts, failures: [])
    }

    func distance(
        from left: SimilarityArtifact,
        to right: SimilarityArtifact,
    ) throws -> Float? {
        similarityTestDistance(from: left, to: right)
    }
}

final class SimilarityDistanceCancellationProbe: Sendable {
    private struct State: Sendable {
        var started = false
        var observedCancellation = false
        var mayReturn = false
        var startWaiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())
    private let releaseGate = NSCondition()

    func distance() -> Float {
        let waiter = state.withLock { state in
            state.started = true
            let waiter = state.startWaiter
            state.startWaiter = nil
            return waiter
        }
        waiter?.resume()
        // This fake implements a synchronous provider call. Hold only that
        // worker until the test has requested cancellation, without a deadline.
        releaseGate.lock()
        while !state.withLock({ $0.mayReturn }) {
            releaseGate.wait()
        }
        releaseGate.unlock()
        state.withLock { $0.observedCancellation = Task.isCancelled }
        return 0
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let alreadyStarted = state.withLock { state in
                if state.started {
                    return true
                }
                state.startWaiter = continuation
                return false
            }
            if alreadyStarted {
                continuation.resume()
            }
        }
    }

    func releaseDistance() {
        releaseGate.lock()
        state.withLock { $0.mayReturn = true }
        releaseGate.broadcast()
        releaseGate.unlock()
    }

    func didObserveCancellation() -> Bool {
        state.withLock { $0.observedCancellation }
    }
}

nonisolated struct CancellationDistanceSimilarityService: RawCullSimilarityServicing {
    let backendDescriptor = similarityTestBackendDescriptor
    let probe: SimilarityDistanceCancellationProbe

    func index(
        sources _: [AIImageSource],
        maxPixelSize _: Int,
        progress _: (@Sendable (RawCullSimilarityIndexingProgress) async -> Void)?,
    ) async throws -> RawCullSimilarityIndexingOutput {
        RawCullSimilarityIndexingOutput(artifacts: [:], failures: [])
    }

    func distance(
        from _: SimilarityArtifact,
        to _: SimilarityArtifact,
    ) throws -> Float? {
        probe.distance()
    }
}

nonisolated let similarityTestBackendDescriptor = SimilarityBackendDescriptor(
    backend: "test-similarity",
    modelFingerprint: "test-model-v1",
    representation: "test-byte",
    preprocessingVersion: "test-preprocess-v1",
    normalizationVersion: "test-normalization-v1",
    configurationVersion: "test-configuration-v1",
)

nonisolated func makeSimilarityTestArtifact(
    source: AIImageSource,
    payload: Data = Data([1]),
) -> SimilarityArtifact {
    SimilarityArtifact(
        descriptor: SimilarityArtifactDescriptor(
            backend: similarityTestBackendDescriptor,
            dimensions: payload.count,
            sourceFingerprint: SourceFingerprint(source: source),
        ),
        payload: payload,
    )
}

nonisolated func similarityTestDistance(
    from left: SimilarityArtifact,
    to right: SimilarityArtifact,
) -> Float? {
    guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
          let leftByte = left.payload.first,
          let rightByte = right.payload.first
    else { return nil }
    return Float(abs(Int(leftByte) - Int(rightByte))) / 255
}

func makeCullingTestFile(
    _ name: String,
    scoreAperture: Double? = nil,
    modificationSeconds: TimeInterval = 0,
    captureSeconds: TimeInterval? = nil,
) -> FileItem {
    let exif = scoreAperture.map {
        ExifMetadata(
            shutterSpeed: nil,
            focalLength: nil,
            aperture: "f/\($0)",
            apertureValue: $0,
            iso: nil,
            isoValue: nil,
            camera: nil,
            lensModel: nil,
            rawFileType: nil,
            rawSizeClass: nil,
            pixelWidth: nil,
            pixelHeight: nil,
        )
    }
    return FileItem(
        url: URL(fileURLWithPath: "/tmp/\(name)"),
        name: name,
        size: 1,
        dateModified: Date(timeIntervalSince1970: modificationSeconds),
        captureDate: captureSeconds.map(Date.init(timeIntervalSince1970:)),
        exifData: exif,
        afFocusNormalized: nil,
    )
}

func makeCullingSharpnessImage(size: Int = 128) -> CGImage? {
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
              data: nil,
              width: size,
              height: size,
              bitsPerComponent: 8,
              bytesPerRow: size * 4,
              space: colorSpace,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
          )
    else { return nil }

    context.setFillColor(gray: 0.08, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.setFillColor(gray: 0.92, alpha: 1)
    let tile = 8
    for y in stride(from: 0, to: size, by: tile) {
        for x in stride(from: 0, to: size, by: tile)
            where (x / tile + y / tile).isMultiple(of: 2) {
            context.fill(CGRect(x: x, y: y, width: tile, height: tile))
        }
    }
    return context.makeImage()
}

func makeCullingBurstResult(groupID: Int, files: [FileItem]) -> BurstAnalysisResult {
    BurstAnalysisResult(
        groupID: groupID,
        fileIDs: files.map(\.id),
        candidates: [],
        recommendedFileID: files.first?.id,
        secondBestFileID: nil,
        confidence: .low,
        reviewState: .needsReview,
        isSafeForOneClickCulling: false,
        reasons: [],
        cautions: [],
    )
}

@MainActor
final class TestBurstAnalysisCacheRepository: BurstAnalysisCacheRepository {
    typealias Load = @MainActor (
        URL,
        [FileItem],
        Int,
        BurstSharpnessSignature,
        BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot?
    typealias MigrationLoad = @MainActor (URL) async -> BurstAnalysisCacheSnapshot?
    typealias Save = @MainActor (BurstAnalysisCacheSnapshot, URL) async -> Void
    typealias Delete = @MainActor (URL) async -> Void

    private let loadHandler: Load
    private let migrationLoadHandler: MigrationLoad
    private let saveHandler: Save
    private let deleteHandler: Delete

    init(
        load: @escaping Load = { _, _, _, _, _ in nil },
        migrationLoad: @escaping MigrationLoad = { _ in nil },
        save: @escaping Save = { _, _ in },
        delete: @escaping Delete = { _ in },
    ) {
        loadHandler = load
        migrationLoadHandler = migrationLoad
        saveHandler = save
        deleteHandler = delete
    }

    func load(
        catalog: URL,
        files: [FileItem],
        thumbnailMaxPixelSize: Int,
        sharpnessSignature: BurstSharpnessSignature,
        similaritySignature: BurstSimilaritySignature,
    ) async -> BurstAnalysisCacheSnapshot? {
        await loadHandler(
            catalog,
            files,
            thumbnailMaxPixelSize,
            sharpnessSignature,
            similaritySignature,
        )
    }

    func loadMigrationCandidate(catalog: URL) async -> BurstAnalysisCacheSnapshot? {
        await migrationLoadHandler(catalog)
    }

    func save(_ snapshot: BurstAnalysisCacheSnapshot, catalog: URL) async {
        await saveHandler(snapshot, catalog)
    }

    func delete(catalog: URL) async {
        await deleteHandler(catalog)
    }
}

actor BurstCacheLoadGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var resultWaiter: CheckedContinuation<BurstAnalysisCacheSnapshot?, Never>?

    func load() async -> BurstAnalysisCacheSnapshot? {
        started = true
        for waiter in startWaiters {
            waiter.resume()
        }
        startWaiters.removeAll()

        return await withCheckedContinuation { continuation in
            resultWaiter = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resume(returning snapshot: BurstAnalysisCacheSnapshot?) {
        resultWaiter?.resume(returning: snapshot)
        resultWaiter = nil
    }
}

actor BurstCacheSaveRecorder {
    private var snapshot: BurstAnalysisCacheSnapshot?
    private var waiters: [CheckedContinuation<BurstAnalysisCacheSnapshot, Never>] = []

    func record(_ snapshot: BurstAnalysisCacheSnapshot) {
        self.snapshot = snapshot
        for waiter in waiters {
            waiter.resume(returning: snapshot)
        }
        waiters.removeAll()
    }

    func waitForSnapshot() async -> BurstAnalysisCacheSnapshot? {
        if let snapshot {
            return snapshot
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

func makeBurstSimilaritySignature(
    sensitivity: Float = 0.25,
) -> BurstSimilaritySignature {
    BurstSimilaritySignature(
        groupingConfig: BurstGroupingConfig(visualDistanceThreshold: sensitivity),
        backendDescriptor: similarityTestBackendDescriptor,
        artifactSchemaVersion: SimilarityArtifactDescriptor.currentSchemaVersion,
        embeddingThumbnailMaxPixelSize: SimilarityScoringModel.embeddingThumbnailMaxPixelSize,
        embeddingPipelineVersion: SimilarityScoringModel.embeddingPipelineVersion,
    )
}

@MainActor
func makeBurstSnapshot(
    catalog: URL,
    files: [FileItem],
    groups: [BurstGroup],
    results: [BurstAnalysisResult],
    reviewStateSnapshots: [BurstReviewStateSnapshot],
    similaritySignature: BurstSimilaritySignature = makeBurstSimilaritySignature(),
) -> BurstAnalysisCacheSnapshot {
    let embeddings = Dictionary(uniqueKeysWithValues: files.map { file in
        let source = SimilarityScoringModel.source(for: file)
        return (
            file.id,
            makeSimilarityTestArtifact(source: source),
        )
    })
    return BurstAnalysisCacheSnapshot(
        schemaVersion: BurstAnalysisCache.schemaVersion,
        algorithmVersion: BurstGroupingConfig.algorithmVersion,
        catalogPath: catalog.path,
        thumbnailMaxPixelSize: 512,
        sharpnessSignature: BurstSharpnessSignature(
            thumbnailMaxPixelSize: 512,
            config: FocusDetectorConfig(),
        ),
        similaritySignature: similaritySignature,
        files: files.map {
            BurstAnalysisCacheFile(
                id: $0.id,
                path: $0.url.path,
                size: $0.size,
                modificationDate: $0.dateModified,
            )
        },
        embeddings: embeddings,
        sharpnessScores: [:],
        saliencyInfo: [:],
        groups: groups,
        boundaryEvidence: [],
        results: results,
        reviewStateSnapshots: reviewStateSnapshots,
        similarityArtifactSetDigest: BurstAnalysisCache.artifactSetDigest(
            files: files,
            artifacts: embeddings,
        ),
    )
}
