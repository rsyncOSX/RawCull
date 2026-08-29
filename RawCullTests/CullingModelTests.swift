import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

private actor SavedFilesRecorder {
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

private actor FailingThenSuccessfulSave {
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

private actor SharpnessScoreURLRecorder {
    private var fileNames: [String] = []

    func record(_ fileName: String) {
        fileNames.append(fileName)
    }

    func recordedFileNames() -> [String] {
        fileNames
    }
}

private actor SimilarityEmbeddingCancellationProbe {
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

private nonisolated struct CancellationSimilarityService: RawCullSimilarityServicing {
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

private nonisolated struct ImmediateSimilarityService: RawCullSimilarityServicing {
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

private actor SimilarityEmbeddingSuspensionProbe {
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

private nonisolated struct SuspendingSimilarityService: RawCullSimilarityServicing {
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

private final class SimilarityDistanceCancellationProbe: Sendable {
    private struct State: Sendable {
        var started = false
        var observedCancellation = false
    }

    private let state = Mutex(State())

    func distance() -> Float {
        state.withLock { $0.started = true }
        let deadline = Date().addingTimeInterval(2)
        while !Task.isCancelled, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.001)
        }
        if Task.isCancelled {
            state.withLock { $0.observedCancellation = true }
        }
        return 0
    }

    func waitUntilStarted() async {
        while !state.withLock({ $0.started }) {
            await Task.yield()
        }
    }

    func didObserveCancellation() -> Bool {
        state.withLock { $0.observedCancellation }
    }
}

private nonisolated struct CancellationDistanceSimilarityService: RawCullSimilarityServicing {
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

private nonisolated let similarityTestBackendDescriptor = SimilarityBackendDescriptor(
    backend: "test-similarity",
    modelFingerprint: "test-model-v1",
    representation: "test-byte",
    preprocessingVersion: "test-preprocess-v1",
    normalizationVersion: "test-normalization-v1",
    configurationVersion: "test-configuration-v1",
)

private nonisolated func makeSimilarityTestArtifact(
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

private nonisolated func similarityTestDistance(
    from left: SimilarityArtifact,
    to right: SimilarityArtifact,
) -> Float? {
    guard left.descriptor.isCompatibleForDistance(with: right.descriptor),
          let leftByte = left.payload.first,
          let rightByte = right.payload.first
    else { return nil }
    return Float(abs(Int(leftByte) - Int(rightByte))) / 255
}

private func makeCullingTestFile(
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

private func makeCullingSharpnessImage(size: Int = 128) -> CGImage? {
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

private func makeCullingBurstResult(groupID: Int, files: [FileItem]) -> BurstAnalysisResult {
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
struct CullingModelTests {
    @Test
    func `scored photo stays unrated while explicit keeper is rated`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.mergeScoringResults(
            [CullingScoringResult(fileName: "scored.ARW", score: 0.7, saliencySubject: nil)],
            in: catalog,
        )
        model.updateRating(fileName: "keeper.ARW", rating: 0, in: catalog)

        #expect(model.isUnrated(photo: "scored.ARW", in: catalog))
        #expect(model.rating(for: "scored.ARW", in: catalog) == nil)
        #expect(!model.isUnrated(photo: "keeper.ARW", in: catalog))
        #expect(model.rating(for: "keeper.ARW", in: catalog) == 0)
        #expect(model.isUnrated(photo: "missing.ARW", in: catalog))
    }

    @Test
    func `restoring unrated state preserves scoring metadata`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        model.mergeScoringResults(
            [CullingScoringResult(fileName: "one.ARW", score: 0.8, saliencySubject: "bird")],
            in: catalog,
        )
        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)

        model.applyRatingStates(
            Dictionary(uniqueKeysWithValues: [("one.ARW", Int?.none)]),
            in: catalog,
        )

        let record = model.savedFiles.first?.filerecords?.first
        #expect(record?.rating == nil)
        #expect(record?.dateTagged == nil)
        #expect(record?.sharpnessScore == 0.8)
        #expect(record?.saliencySubject == "bird")
    }

    @Test
    func `corrupt load blocks mutations and preserves in-memory state`() {
        let url = URL(fileURLWithPath: "/tmp/savedfiles-\(UUID().uuidString).json")
        let failure = SavedFilesReadFailure(url: url, message: "Malformed JSON")
        let model = CullingModel(
            saveDelayNanoseconds: 0,
            saveHandler: { _ in },
            loadHandler: { .failed(failure) },
        )
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        #expect(!model.loadSavedFiles())
        model.updateRating(fileName: "one.ARW", rating: 5, in: catalog)

        #expect(model.savedFiles.isEmpty)
        #expect(model.persistenceLoadFailure == failure)
        #expect(model.persistenceError != nil)
    }

    @Test
    func `hasExplicitRatings requires a non-nil rating in the requested catalog`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let otherCatalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.mergeScoringResults(
            [CullingScoringResult(fileName: "unrated.ARW", score: 0.75, saliencySubject: nil)],
            in: catalog,
        )

        #expect(!model.hasExplicitRatings(in: catalog))
        #expect(!model.hasExplicitRatings(in: otherCatalog))

        model.updateRating(fileName: "rejected.ARW", rating: -1, in: catalog)
        #expect(model.hasExplicitRatings(in: catalog))
    }

    @Test
    func `explicit rating count excludes scoring-only records`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.mergeScoringResults(
            [CullingScoringResult(fileName: "scored.ARW", score: 0.75, saliencySubject: nil)],
            in: catalog,
        )
        model.updateRating(fileName: "rated.ARW", rating: -1, in: catalog)

        #expect(model.explicitRatingCount(in: catalog) == 1)
    }

    @Test
    func `cancelling similarity ranking stops its owned distance helper`() async {
        let probe = SimilarityDistanceCancellationProbe()
        let model = SimilarityScoringModel(
            similarityService: CancellationDistanceSimilarityService(probe: probe),
            artifactStore: makeIsolatedSimilarityArtifactStore(),
        )
        let anchor = makeCullingTestFile("ranking-anchor.ARW")
        let candidate = makeCullingTestFile("ranking-candidate.ARW")
        let previousAnchorID = UUID()
        let previousDistanceID = UUID()
        model.embeddings = [
            anchor.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: anchor)),
            candidate.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: candidate))
        ]
        model.anchorFileID = previousAnchorID
        model.distances = [previousDistanceID: 0.5]

        let ranking = Task {
            await model.rankSimilar(
                to: anchor.id,
                using: [anchor, candidate],
            )
        }
        await probe.waitUntilStarted()
        ranking.cancel()
        await ranking.value

        #expect(probe.didObserveCancellation())
        #expect(model.anchorFileID == previousAnchorID)
        #expect(model.distances == [previousDistanceID: 0.5])
        #expect(model.sortBySimilarity == false)
    }

    @Test
    func `disarming similarity ranking preserves the last completed order`() async {
        let probe = SimilarityDistanceCancellationProbe()
        let model = SimilarityScoringModel(
            similarityService: CancellationDistanceSimilarityService(probe: probe),
            artifactStore: makeIsolatedSimilarityArtifactStore(),
        )
        let anchor = makeCullingTestFile("replacement-anchor.ARW")
        let candidate = makeCullingTestFile("replacement-candidate.ARW")
        let previousAnchorID = UUID()
        let previousDistances: [UUID: Float] = [UUID(): 0.25]
        model.embeddings = [
            anchor.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: anchor)),
            candidate.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: candidate))
        ]
        model.anchorFileID = previousAnchorID
        model.distances = previousDistances
        model.sortBySimilarity = true

        let ranking = Task {
            await model.rankSimilar(
                to: anchor.id,
                using: [anchor, candidate],
            )
        }
        await probe.waitUntilStarted()
        model.cancelSimilarityRanking()
        model.sortBySimilarity = false
        await ranking.value

        #expect(probe.didObserveCancellation())
        #expect(model.anchorFileID == previousAnchorID)
        #expect(model.distances == previousDistances)
        #expect(model.sortBySimilarity == false)
    }

    @Test
    func `find similar indexes a fresh catalog before ranking`() async {
        let viewModel = RawCullViewModel(
            similarityService: ImmediateSimilarityService(),
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
        )
        let anchor = makeCullingTestFile("fresh-anchor.ARW")
        let candidate = makeCullingTestFile("fresh-candidate.ARW")
        viewModel.files = [anchor, candidate]
        viewModel.filteredFiles = [anchor, candidate]
        viewModel.selectedFileID = anchor.id

        #expect(!viewModel.similarityModel.hasCompleteSimilarityIndex(for: viewModel.files))

        await viewModel.findSimilarToSelected()

        #expect(viewModel.similarityModel.hasCompleteSimilarityIndex(for: viewModel.files))
        #expect(viewModel.similarityModel.anchorFileID == anchor.id)
        #expect(viewModel.similarityModel.distances[candidate.id] != nil)
        #expect(viewModel.similarityModel.sortBySimilarity)
        #expect(viewModel.filteredFiles.first?.id == anchor.id)
    }

    @Test
    func `similarity indexing cancellation stops structured embedding workers`() async {
        let probe = SimilarityEmbeddingCancellationProbe()
        let model = SimilarityScoringModel(
            similarityService: CancellationSimilarityService(probe: probe),
            artifactStore: makeIsolatedSimilarityArtifactStore(),
        )
        let files = (0 ..< 8).map { makeCullingTestFile("cancel-\($0).ARW") }

        let indexingTask = Task {
            await model.indexFiles(files)
        }
        await probe.waitUntilStarted(4)
        model.cancelIndexing()
        await indexingTask.value
        let counts = await probe.counts()

        #expect(counts.started == 4)
        #expect(counts.cancelled == 4)
        #expect(model.embeddings.isEmpty)
        #expect(model.isIndexing == false)
        #expect(model.indexingProgress == 0)
        #expect(model.indexingTotal == 0)
    }

    @Test
    func `superseded similarity indexing cannot commit or clear newer run state`() async {
        let probe = SimilarityEmbeddingSuspensionProbe()
        let model = SimilarityScoringModel(
            similarityService: SuspendingSimilarityService(probe: probe),
            artifactStore: makeIsolatedSimilarityArtifactStore(),
        )
        let slowFile = makeCullingTestFile("slow.ARW")
        let fastFile = makeCullingTestFile("fast.ARW")

        let oldRun = Task {
            await model.indexFiles([slowFile])
        }
        await probe.waitUntilStarted(1)
        await model.indexFiles([fastFile])

        #expect(model.embeddings[fastFile.id]?.payload == Data([2]))
        #expect(model.embeddings[slowFile.id] == nil)
        #expect(model.isIndexing == false)

        await probe.releaseAll()
        await oldRun.value

        #expect(model.embeddings[fastFile.id]?.payload == Data([2]))
        #expect(model.embeddings[slowFile.id] == nil)
        #expect(model.isIndexing == false)
        #expect(model.indexingProgress == 0)
        #expect(model.indexingTotal == 0)
    }

    @Test
    func `updateRating creates catalog record and debounced save snapshot`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)
        let snapshots = await recorder.waitForSnapshotCount(1)

        #expect(model.explicitRatingCount(in: catalog) == 1)
        #expect(model.savedFiles.first?.catalog == catalog)
        #expect(model.savedFiles.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(model.savedFiles.first?.filerecords?.first?.rating == 3)
        #expect(snapshots.last?.first?.filerecords?.first?.rating == 3)
    }

    @Test
    func `failed persistence remains dirty and retry saves newest snapshot`() async {
        let saver = FailingThenSuccessfulSave()
        let model = CullingModel(saveDelayNanoseconds: 0) { snapshot in
            try await saver.save(snapshot)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)
        for _ in 0 ..< 200 where model.persistenceError == nil {
            await Task.yield()
        }

        #expect(model.hasUnsavedChanges)
        #expect(model.persistenceError != nil)

        model.updateRating(fileName: "two.ARW", rating: 5, in: catalog)
        await model.retryPersistence()

        let state = await saver.state()
        #expect(state.attempts >= 2)
        #expect(state.snapshots.last?.first?.filerecords?.count == 2)
        #expect(!model.hasUnsavedChanges)
        #expect(model.persistenceError == nil)
    }

    @Test
    func `updateRatings and applyRatings upsert existing records`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog)
        model.applyRatings(["two.ARW": -1, "three.ARW": 5], in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        let records = model.savedFiles.first?.filerecords ?? []
        let ratings = Dictionary(uniqueKeysWithValues: records.compactMap { record -> (String, Int)? in
            guard let fileName = record.fileName, let rating = record.rating else { return nil }
            return (fileName, rating)
        })

        #expect(ratings == ["one.ARW": 2, "two.ARW": -1, "three.ARW": 5])
    }

    @Test
    func `mergeScoringResults preserves ratings and writes scores`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 4, in: catalog)
        model.mergeScoringResults(
            [CullingScoringResult(fileName: "one.ARW", score: 0.75, saliencySubject: "bird")],
            in: catalog,
        )
        _ = await recorder.waitForSnapshotCount(1)

        let record = model.savedFiles.first?.filerecords?.first
        #expect(record?.rating == 4)
        #expect(record?.sharpnessScore == 0.75)
        #expect(record?.saliencySubject == "bird")
    }

    @Test
    func `resetSavedFiles clears records for catalog`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog)
        model.resetSavedFiles(in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        #expect(model.explicitRatingCount(in: catalog) == 0)
        #expect(model.savedFiles.first?.filerecords == [])
    }

    @Test
    func `manual winner override requires exact membership`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        model.upsertBurstWinnerOverride(
            BurstWinnerOverride(
                winnerFileName: "A.ARW",
                memberFileNames: ["A.ARW", "B.ARW", "C.ARW"],
            ),
            in: catalog,
        )

        let matching = [
            makeCullingTestFile("C.ARW"),
            makeCullingTestFile("A.ARW"),
            makeCullingTestFile("B.ARW")
        ]
        let changed = [
            makeCullingTestFile("A.ARW"),
            makeCullingTestFile("X.ARW"),
            makeCullingTestFile("Y.ARW")
        ]

        #expect(model.overrideWinner(for: matching, in: catalog)?.winnerFileName == "A.ARW")
        #expect(model.overrideWinner(for: changed, in: catalog) == nil)
    }

    @Test
    func `upsert preserves same winner for different member sets`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.upsertBurstWinnerOverride(
            BurstWinnerOverride(winnerFileName: "A.ARW", memberFileNames: ["A.ARW", "B.ARW"]),
            in: catalog,
        )
        model.upsertBurstWinnerOverride(
            BurstWinnerOverride(winnerFileName: "A.ARW", memberFileNames: ["A.ARW", "C.ARW"]),
            in: catalog,
        )

        #expect(model.burstWinnerOverrides(in: catalog).count == 2)
        #expect(model.overrideWinner(
            for: [makeCullingTestFile("A.ARW"), makeCullingTestFile("B.ARW")],
            in: catalog,
        )?.winnerFileName == "A.ARW")
        #expect(model.overrideWinner(
            for: [makeCullingTestFile("A.ARW"), makeCullingTestFile("C.ARW")],
            in: catalog,
        )?.winnerFileName == "A.ARW")
    }

    @Test
    func `prune removes overrides with missing winner or member`() {
        let model = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.upsertBurstWinnerOverride(
            BurstWinnerOverride(winnerFileName: "A.ARW", memberFileNames: ["A.ARW", "B.ARW"]),
            in: catalog,
        )
        model.upsertBurstWinnerOverride(
            BurstWinnerOverride(winnerFileName: "C.ARW", memberFileNames: ["C.ARW", "D.ARW"]),
            in: catalog,
        )

        model.pruneStaleBurstOverrides(validFileNames: ["A.ARW"], in: catalog)

        #expect(model.burstWinnerOverrides(in: catalog).isEmpty)
    }

    @Test
    func `FileRecord equality includes persisted sharpness metadata`() {
        let lhs = FileRecord(
            fileName: "one.ARW",
            dateTagged: "now",
            dateCopied: nil,
            rating: 3,
            sharpnessScore: 0.5,
            saliencySubject: "bird",
            sharpnessScoringSignature: nil,
            sharpnessFileSize: 10,
            sharpnessModificationDate: Date(timeIntervalSince1970: 1),
        )
        let rhs = FileRecord(
            fileName: "one.ARW",
            dateTagged: "now",
            dateCopied: nil,
            rating: 3,
            sharpnessScore: 0.9,
            saliencySubject: "bird",
            sharpnessScoringSignature: nil,
            sharpnessFileSize: 10,
            sharpnessModificationDate: Date(timeIntervalSince1970: 1),
        )

        #expect(lhs != rhs)
    }

    @Test
    func `SavedFiles equality includes records and burst overrides`() {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let lhs = SavedFiles(
            catalog: catalog,
            dateStart: "now",
            filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 2),
        )
        let rhs = SavedFiles(
            catalog: catalog,
            dateStart: "now",
            filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
        )

        #expect(lhs != rhs)
    }

    @Test
    func `updateRating recreates records after reset leaves empty catalog`() async {
        let recorder = SavedFilesRecorder()
        let model = CullingModel(saveDelayNanoseconds: 0) { savedFiles in
            await recorder.record(savedFiles)
        }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        model.updateRating(fileName: "one.ARW", rating: 3, in: catalog)
        model.resetSavedFiles(in: catalog)
        model.updateRating(fileName: "two.ARW", rating: 5, in: catalog)
        _ = await recorder.waitForSnapshotCount(1)

        let records = model.savedFiles.first?.filerecords ?? []
        #expect(records.count == 1)
        #expect(records.first?.fileName == "two.ARW")
        #expect(records.first?.rating == 5)
    }
}

@MainActor
struct SavedFilesJSONTests {
    @Test
    func `reader distinguishes missing and corrupt stores`() throws {
        let missingURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: missingURL)
        defer { try? FileManager.default.removeItem(at: root) }

        guard case let .missing(readURL) = ReadSavedFilesJSON(savedFilesURL: missingURL).read() else {
            Issue.record("Expected a missing-store result")
            return
        }
        #expect(readURL == missingURL)

        try FileManager.default.createDirectory(
            at: missingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data("{not-json".utf8).write(to: missingURL)

        guard case let .failed(failure) = ReadSavedFilesJSON(savedFilesURL: missingURL).read() else {
            Issue.record("Expected a corrupt-store failure")
            return
        }
        #expect(failure.url == missingURL)
        #expect(try Data(contentsOf: missingURL) == Data("{not-json".utf8))
    }

    @Test
    func `second write preserves previous store as backup`() async throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        var saved = SavedFiles(
            catalog: catalog,
            dateStart: "now",
            filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 2),
        )
        try await WriteSavedFilesJSON.write([saved], to: fileURL)
        saved.filerecords?[0].rating = 5

        try await WriteSavedFilesJSON.write([saved], to: fileURL)

        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("savedfiles.backup.json")
        let backup = try JSONDecoder().decode([DecodeSavedFiles].self, from: Data(contentsOf: backupURL))
        #expect(backup.first?.filerecords?.first?.rating == 2)
    }

    @Test
    func `write creates Application Support directory and saved files JSON`() async throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "one.ARW", dateTagged: nil, dateCopied: nil, rating: 4),
            )
        ]

        try await WriteSavedFilesJSON.write(savedFiles, to: fileURL)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let data = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: data)
        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 4)
    }

    @Test
    func `older saved files JSON decodes`() throws {
        let json = """
        [{
          "catalog": "file:///tmp/catalog/",
          "dateStart": "19 May 2026 12:00",
          "filerecords": [{
            "fileName": "one.ARW",
            "rating": 3
          }]
        }]
        """
        let decoded = try JSONDecoder().decode([DecodeSavedFiles].self, from: Data(json.utf8))
        let saved = try #require(decoded.first.map(SavedFiles.init))

        #expect(saved.catalog == URL(string: "file:///tmp/catalog/"))
        #expect(saved.filerecords?.first?.fileName == "one.ARW")
    }

    @Test
    func `read loads saved files from Application Support URL`() throws {
        let fileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: fileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let savedFiles = [
            SavedFiles(
                catalog: catalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "two.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            )
        ]
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let data = try JSONEncoder().encode(savedFiles)
        try data.write(to: fileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: fileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == catalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "two.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    @Test
    func `read ignores old Documents file when Application Support file exists`() throws {
        let newFileURL = makeIsolatedSavedFilesURL()
        let root = savedFilesTestRoot(for: newFileURL)
        defer { try? FileManager.default.removeItem(at: root) }
        let oldFileURL = root
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("savedfiles.json")
        let newCatalog = URL(fileURLWithPath: "/tmp/new-catalog-\(UUID().uuidString)")
        let oldCatalog = URL(fileURLWithPath: "/tmp/old-catalog-\(UUID().uuidString)")
        let newSavedFiles = [
            SavedFiles(
                catalog: newCatalog,
                dateStart: "19 May 2026 12:00",
                filerecord: FileRecord(fileName: "new.ARW", dateTagged: nil, dateCopied: nil, rating: 5),
            )
        ]
        let oldSavedFiles = [
            SavedFiles(
                catalog: oldCatalog,
                dateStart: "18 May 2026 12:00",
                filerecord: FileRecord(fileName: "old.ARW", dateTagged: nil, dateCopied: nil, rating: 1),
            )
        ]
        try FileManager.default.createDirectory(
            at: newFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try FileManager.default.createDirectory(
            at: oldFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try JSONEncoder().encode(newSavedFiles).write(to: newFileURL)
        try JSONEncoder().encode(oldSavedFiles).write(to: oldFileURL)

        let decoded = try #require(ReadSavedFilesJSON(savedFilesURL: newFileURL).readjsonfilesavedfiles())

        #expect(decoded.first?.catalog == newCatalog)
        #expect(decoded.first?.filerecords?.first?.fileName == "new.ARW")
        #expect(decoded.first?.filerecords?.first?.rating == 5)
    }

    private func savedFilesTestRoot(for fileURL: URL) -> URL {
        fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
struct RawCullViewModelCullingTests {
    @Test
    func `rebuildRatingCache populates ratings and tagged filenames for selected catalog`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.cullingModel.updateRatings(fileNames: ["one.ARW", "two.ARW"], rating: 2, in: catalog.url)
        viewModel.cullingModel.mergeScoringResults(
            [CullingScoringResult(fileName: "scored.ARW", score: 0.7, saliencySubject: nil)],
            in: catalog.url,
        )

        viewModel.rebuildRatingCache()

        #expect(viewModel.ratingCache == ["one.ARW": 2, "two.ARW": 2])
        #expect(viewModel.taggedNamesCache == ["one.ARW", "two.ARW"])
    }

    @Test
    func `passesRatingFilter distinguishes rejected keepers and star ratings`() {
        let viewModel = RawCullViewModel()
        let rejected = makeCullingTestFile("rejected.ARW")
        let keeper = makeCullingTestFile("keeper.ARW")
        let unrated = makeCullingTestFile("unrated.ARW")
        let star = makeCullingTestFile("star.ARW")
        viewModel.ratingCache = [
            rejected.name: -1,
            keeper.name: 0,
            star.name: 4
        ]

        viewModel.ratingFilter = .rejected
        #expect(viewModel.passesRatingFilter(rejected))
        #expect(!viewModel.passesRatingFilter(keeper))

        viewModel.ratingFilter = .keepers
        #expect(viewModel.passesRatingFilter(keeper))
        #expect(!viewModel.passesRatingFilter(unrated))
        #expect(!viewModel.passesRatingFilter(star))

        viewModel.ratingFilter = .stars(4)
        #expect(viewModel.passesRatingFilter(star))
        #expect(!viewModel.passesRatingFilter(rejected))
    }

    @Test
    func `preselectFirstVisibleFileByName selects alphabetically first visible file`() {
        let viewModel = RawCullViewModel()
        let c = makeCullingTestFile("C.ARW")
        let a = makeCullingTestFile("A.ARW")
        let b = makeCullingTestFile("B.ARW")
        viewModel.files = [c, a, b]
        viewModel.filteredFiles = [c, a, b]

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == a.id)
    }

    @Test
    func `preselectFirstVisibleFileByName replaces previous selection`() {
        let viewModel = RawCullViewModel()
        let previous = makeCullingTestFile("previous.ARW")
        let c = makeCullingTestFile("C.ARW")
        let a = makeCullingTestFile("A.ARW")
        let b = makeCullingTestFile("B.ARW")
        viewModel.files = [previous, c, a, b]
        viewModel.filteredFiles = [c, a, b]
        viewModel.selectedFileID = previous.id

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == a.id)
    }

    @Test
    func `preselectFirstVisibleFileByName clears selection when no files are visible`() {
        let viewModel = RawCullViewModel()
        let previous = makeCullingTestFile("previous.ARW")
        viewModel.files = [previous]
        viewModel.filteredFiles = []
        viewModel.selectedFileID = previous.id

        viewModel.preselectFirstVisibleFileByName()

        #expect(viewModel.selectedFileID == nil)
    }

    @Test
    func `burst analysis targets selected thumbnails before rating filter`() {
        let viewModel = RawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let selectedLater = makeCullingTestFile("C-selected.ARW")
        let selectedEarlier = makeCullingTestFile("A-selected.ARW")
        viewModel.files = [twoStar, selectedLater, selectedEarlier]
        viewModel.ratingCache = [twoStar.name: 2]
        viewModel.ratingFilter = .stars(2)
        viewModel.selectedFileIDs = [selectedLater.id, selectedEarlier.id]

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == ["A-selected.ARW", "C-selected.ARW"])
    }

    @Test
    func `burst analysis targets exact active star rating`() {
        let viewModel = RawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let fourStar = makeCullingTestFile("A-four-star.ARW")
        let unrated = makeCullingTestFile("C-unrated.ARW")
        viewModel.files = [twoStar, fourStar, unrated]
        viewModel.ratingCache = [
            twoStar.name: 2,
            fourStar.name: 4
        ]
        viewModel.ratingFilter = .stars(2)

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == ["B-two-star.ARW"])
    }

    @Test
    func `burst analysis keeps full catalog for unscoped filters`() {
        let viewModel = RawCullViewModel()
        let rejected = makeCullingTestFile("C-rejected.ARW")
        let keeper = makeCullingTestFile("A-keeper.ARW")
        let rated = makeCullingTestFile("B-rated.ARW")
        viewModel.files = [rejected, keeper, rated]
        viewModel.ratingCache = [
            rejected.name: -1,
            rated.name: 3
        ]

        let expectedNames = ["A-keeper.ARW", "B-rated.ARW", "C-rejected.ARW"]

        viewModel.ratingFilter = .all
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .keepers
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .rejected
        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == expectedNames)
    }

    @Test
    func `burst analysis orders shots by capture date with file-date fallback`() {
        let viewModel = RawCullViewModel()
        let latest = makeCullingTestFile("A-latest.ARW", captureSeconds: 30)
        let earliest = makeCullingTestFile("Z-earliest.ARW", captureSeconds: 10)
        let fallback = makeCullingTestFile("M-fallback.ARW", modificationSeconds: 20)
        viewModel.files = [latest, fallback, earliest]

        #expect(viewModel.burstAnalysisTargetFiles.map(\.name) == [
            "Z-earliest.ARW",
            "M-fallback.ARW",
            "A-latest.ARW"
        ])
    }

    @Test
    func `sharpness scoring targets selected thumbnails before rating filter`() {
        let viewModel = RawCullViewModel()
        let twoStar = makeCullingTestFile("B-two-star.ARW")
        let selectedLater = makeCullingTestFile("C-selected.ARW")
        let selectedEarlier = makeCullingTestFile("A-selected.ARW")
        viewModel.files = [twoStar, selectedLater, selectedEarlier]
        viewModel.filteredFiles = [twoStar, selectedLater, selectedEarlier]
        viewModel.ratingCache = [twoStar.name: 2]
        viewModel.ratingFilter = .stars(2)
        viewModel.selectedFileIDs = [selectedLater.id, selectedEarlier.id]

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == ["C-selected.ARW", "A-selected.ARW"])
    }

    @Test
    func `sharpness scoring targets active star rating in visible order`() {
        let viewModel = RawCullViewModel()
        let firstVisible = makeCullingTestFile("D-two-star.ARW")
        let secondVisible = makeCullingTestFile("B-two-star.ARW")
        let fourStar = makeCullingTestFile("A-four-star.ARW")
        viewModel.files = [secondVisible, fourStar, firstVisible]
        viewModel.filteredFiles = [firstVisible, secondVisible, fourStar]
        viewModel.ratingCache = [
            firstVisible.name: 2,
            secondVisible.name: 2,
            fourStar.name: 4
        ]
        viewModel.ratingFilter = .stars(2)

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == ["D-two-star.ARW", "B-two-star.ARW"])
    }

    @Test
    func `sharpness scoring falls back to filename sorted catalog for non-star filters`() {
        let viewModel = RawCullViewModel()
        let rejected = makeCullingTestFile("C-rejected.ARW")
        let keeper = makeCullingTestFile("A-keeper.ARW")
        let rated = makeCullingTestFile("B-rated.ARW")
        viewModel.files = [rejected, keeper, rated]
        viewModel.filteredFiles = [rated]
        viewModel.ratingCache = [
            rejected.name: -1,
            rated.name: 3
        ]

        let expectedNames = ["A-keeper.ARW", "B-rated.ARW", "C-rejected.ARW"]

        viewModel.ratingFilter = .all
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .keepers
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)

        viewModel.ratingFilter = .rejected
        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == expectedNames)
    }

    @Test
    func `sharpness scoring appends hidden selected files after visible selected files`() {
        let viewModel = RawCullViewModel()
        let visibleSelected = makeCullingTestFile("C-visible-selected.ARW")
        let visibleUnselected = makeCullingTestFile("B-visible-unselected.ARW")
        let hiddenSelected = makeCullingTestFile("A-hidden-selected.ARW")
        viewModel.files = [visibleSelected, visibleUnselected, hiddenSelected]
        viewModel.filteredFiles = [visibleSelected, visibleUnselected]
        viewModel.selectedFileIDs = [visibleSelected.id, hiddenSelected.id]

        #expect(viewModel.sharpnessScoringTargetFiles.map(\.name) == [
            "C-visible-selected.ARW",
            "A-hidden-selected.ARW"
        ])
    }

    @Test
    func `calibrateAndScoreCurrentCatalog scores and persists only target files`() async throws {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let selectedVisible = makeCullingTestFile("B-selected-visible.ARW")
        let selectedHidden = makeCullingTestFile("A-selected-hidden.ARW")
        let unselected = makeCullingTestFile("C-unselected.ARW")
        let recorder = SharpnessScoreURLRecorder()

        viewModel.selectedSource = catalog
        viewModel.files = [unselected, selectedHidden, selectedVisible]
        viewModel.filteredFiles = [selectedVisible, unselected]
        viewModel.selectedFileIDs = [selectedVisible.id, selectedHidden.id]
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        let image = try #require(makeCullingSharpnessImage())
        let adapter = RawCullPhotoAnalysisAdapter(
            inputLoaderOverride: { file, _, _ in
                await recorder.record(file.url.lastPathComponent)
                return PhotoAnalysisInput(
                    image: image,
                    iso: file.iso,
                    aperture: file.aperture,
                    normalizedAFPoint: file.normalizedAFPoint,
                )
            },
        )
        viewModel.sharpnessModel = SharpnessScoringModel(
            analysisAdapterOverride: adapter,
        )

        await viewModel.calibrateAndScoreCurrentCatalog()

        let scoredFileNames = await recorder.recordedFileNames()
        #expect(Set(scoredFileNames) == ["A-selected-hidden.ARW", "B-selected-visible.ARW"])
        #expect(Set(viewModel.sharpnessModel.scores.keys) == [selectedHidden.id, selectedVisible.id])

        let records = viewModel.cullingModel.savedFiles.first?.filerecords ?? []
        #expect(Set(records.compactMap(\.fileName)) == ["A-selected-hidden.ARW", "B-selected-visible.ARW"])
        #expect(!records.contains { $0.fileName == unselected.name })
    }

    @Test
    func `extractRatedfilenames returns files at or above requested rating`() {
        let viewModel = RawCullViewModel()
        let files = [
            makeCullingTestFile("two.ARW"),
            makeCullingTestFile("four.ARW"),
            makeCullingTestFile("unrated.ARW")
        ]
        viewModel.filteredFiles = files
        viewModel.ratingCache = [
            "two.ARW": 2,
            "four.ARW": 4
        ]

        #expect(viewModel.extractRatedfilenames(3) == ["four.ARW"])
    }

    @Test
    func `bulk updateRating updates culling model and cache`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: files, rating: 5)

        #expect(viewModel.ratingCache == ["one.ARW": 5, "two.ARW": 5])
    }

    @Test
    func `rating mutations refresh the active rating-filter count`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("one.ARW")
        let second = makeCullingTestFile("two.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.catalogDisplayCandidates = [first, second]
        viewModel.filteredFiles = [first, second]
        viewModel.ratingFilter = .stars(3)
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: first, rating: 3)
        #expect(viewModel.filteredFiles.map(\.name) == ["one.ARW"])

        viewModel.updateRating(for: second, rating: 3)
        #expect(viewModel.filteredFiles.map(\.name) == ["one.ARW", "two.ARW"])

        viewModel.updateRating(for: first, rating: 2)
        #expect(viewModel.filteredFiles.map(\.name) == ["two.ARW"])
    }

    @Test
    func `clear all culling state synchronizes caches filters and persisted data`() async {
        let recorder = SavedFilesRecorder()
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let file = makeCullingTestFile("one.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = [file]
        viewModel.catalogDisplayCandidates = [file]
        viewModel.filteredFiles = [file]
        viewModel.ratingFilter = .stars(3)
        viewModel.cullingModel = CullingModel(
            saveDelayNanoseconds: 30_000_000_000,
            saveHandler: { snapshot in await recorder.record(snapshot) },
        )
        viewModel.updateRating(for: file, rating: 3)

        viewModel.clearAllCullingState()
        let didSave = await viewModel.cullingModel.flushPersistence()
        let snapshots = await recorder.waitForSnapshotCount(1)

        #expect(didSave)
        #expect(viewModel.cullingModel.savedFiles.isEmpty)
        #expect(viewModel.ratingCache.isEmpty)
        #expect(viewModel.taggedNamesCache.isEmpty)
        #expect(viewModel.filteredFiles.isEmpty)
        #expect(snapshots.last?.isEmpty == true)
    }

    @Test
    func `applying Deep Review winner rates it three stars and marks group reviewed`() throws {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let winner = files[1]
        let groupID = 7
        let signature = try #require(BurstGroupSignature(files: files, catalog: catalog.url))
        let result = DeepAIReviewResult(
            groupID: groupID,
            groupSignature: signature,
            preset: .auto,
            candidates: [],
            recommendedFileID: winner.id,
            confidence: .high,
            reasons: [.strongestSubjectDetail],
            cautions: [],
            timestamp: Date(timeIntervalSince1970: 0),
        )
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })
        viewModel.similarityModel.burstGroups = [BurstGroup(id: groupID, fileIDs: files.map(\.id))]
        viewModel.similarityModel.burstGroupLookup = Dictionary(
            uniqueKeysWithValues: files.map { ($0.id, groupID) },
        )
        viewModel.burstAnalysisResults[groupID] = makeCullingBurstResult(groupID: groupID, files: files)
        viewModel.updateRating(for: files[0], rating: 2)

        viewModel.applyDeepAIReviewRecommendation(result, to: files)

        #expect(viewModel.ratingCache == [files[0].name: 2, winner.name: 3])
        #expect(viewModel.burstReviewStates[groupID] == .reviewed)
        #expect(viewModel.burstAnalysisResults[groupID]?.reviewState == .reviewed)
        #expect(viewModel.cullingModel.overrideWinner(for: files, in: catalog.url)?.winnerFileName == winner.name)
    }

    @Test
    func `updateRatingAndAdvance rates current file and selects next visible file`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: 3, in: files)

        #expect(viewModel.selectedFileID == files[1].id)
        #expect(viewModel.ratingCache == ["one.ARW": 3])
        #expect(viewModel.cullingModel.savedFiles.first?.filerecords?.first?.fileName == "one.ARW")
        #expect(viewModel.cullingModel.savedFiles.first?.filerecords?.first?.rating == 3)
    }

    @Test(arguments: [-1, 0, 2, 3, 4, 5])
    func `updateRatingAndAdvance marks active burst reviewed`(_ rating: Int) {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let groupID = 7
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.activeBurstComparisonGroupID = groupID
        viewModel.burstAnalysisResults[groupID] = makeCullingBurstResult(groupID: groupID, files: files)
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: rating, in: files)

        #expect(viewModel.ratingCache == [files[0].name: rating])
        #expect(viewModel.burstReviewStates[groupID] == .reviewed)
        #expect(viewModel.burstAnalysisResults[groupID]?.reviewState == .reviewed)
    }

    @Test
    func `updateRatingAndAdvance leaves last visible file selected`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.selectedSource = catalog
        viewModel.files = files
        viewModel.selectedFileID = files[1].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[1], rating: 5, in: files)

        #expect(viewModel.selectedFileID == files[1].id)
        #expect(viewModel.ratingCache == ["two.ARW": 5])
    }

    @Test
    func `updateRatingAndAdvance without catalog leaves rating and selection unchanged`() {
        let viewModel = RawCullViewModel()
        let files = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        viewModel.files = files
        viewModel.selectedFileID = files[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: files[0], rating: 4, in: files)

        #expect(viewModel.selectedFileID == files[0].id)
        #expect(viewModel.ratingCache.isEmpty)
        #expect(viewModel.cullingModel.savedFiles.isEmpty)
    }

    @Test
    func `updateRatingAndAdvance with file outside visible order does not change selection`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let visible = [makeCullingTestFile("one.ARW"), makeCullingTestFile("two.ARW")]
        let hidden = makeCullingTestFile("hidden.ARW")
        viewModel.selectedSource = catalog
        viewModel.files = visible + [hidden]
        viewModel.selectedFileID = visible[0].id
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRatingAndAdvance(for: hidden, rating: 2, in: visible)

        #expect(viewModel.selectedFileID == visible[0].id)
        #expect(viewModel.ratingCache == ["hidden.ARW": 2])
    }

    @Test
    func `clearCurrentCatalogCullingState allows rating same catalog again`() {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let first = makeCullingTestFile("one.ARW")
        let second = makeCullingTestFile("two.ARW")
        viewModel.selectedSource = catalog
        viewModel.cullingModel = CullingModel(saveDelayNanoseconds: 0, saveHandler: { _ in })

        viewModel.updateRating(for: first, rating: 3)
        viewModel.clearCurrentCatalogCullingState()
        viewModel.updateRating(for: second, rating: 5)

        let records = viewModel.cullingModel.savedFiles.first?.filerecords ?? []
        #expect(records.count == 1)
        #expect(records.first?.fileName == "two.ARW")
        #expect(records.first?.rating == 5)
        #expect(viewModel.ratingCache == ["two.ARW": 5])
        #expect(viewModel.taggedNamesCache == ["two.ARW"])
    }

    @Test
    func `burst signatures are order independent and catalog relative`() throws {
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = FileItem(
            url: catalog.appendingPathComponent("day1/duplicate.ARW"),
            name: "duplicate.ARW",
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )
        let second = FileItem(
            url: catalog.appendingPathComponent("day2/duplicate.ARW"),
            name: "duplicate.ARW",
            size: 1,
            dateModified: Date(timeIntervalSince1970: 0),
            exifData: nil,
            afFocusNormalized: nil,
        )

        let lhs = try #require(BurstGroupSignature(files: [first, second], catalog: catalog))
        let rhs = try #require(BurstGroupSignature(files: [second, first], catalog: catalog))

        #expect(lhs == rhs)
        #expect(lhs.memberKeys == ["day1/duplicate.ARW", "day2/duplicate.ARW"])
    }

    @Test
    func `cached review state restores by signature after file id remap`() throws {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let oldA = makeCullingTestFile("A.ARW")
        let oldB = makeCullingTestFile("B.ARW")
        let currentA = makeCullingTestFile("A.ARW")
        let currentB = makeCullingTestFile("B.ARW")
        let signature = try #require(BurstGroupSignature(files: [oldA, oldB], catalog: catalog.url))

        viewModel.selectedSource = catalog
        viewModel.files = [currentA, currentB]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 9, fileIDs: [currentA.id, currentB.id])]

        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [oldA, oldB],
            groups: [BurstGroup(id: 1, fileIDs: [oldA.id, oldB.id])],
            results: [],
            reviewStateSnapshots: [BurstReviewStateSnapshot(signature: signature, state: .decisionApplied)],
        )

        let states = viewModel.cachedReviewStates(from: snapshot)

        #expect(states == [9: .decisionApplied])
    }

    @Test
    func `cached review state ignores matching group id with changed membership`() throws {
        let viewModel = RawCullViewModel()
        let catalog = ARWSourceCatalog(name: "Catalog", url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"))
        let oldA = makeCullingTestFile("A.ARW")
        let oldB = makeCullingTestFile("B.ARW")
        let currentA = makeCullingTestFile("A.ARW")
        let currentC = makeCullingTestFile("C.ARW")
        let signature = try #require(BurstGroupSignature(files: [oldA, oldB], catalog: catalog.url))

        viewModel.selectedSource = catalog
        viewModel.files = [currentA, currentC]
        viewModel.similarityModel.burstGroups = [BurstGroup(id: 1, fileIDs: [currentA.id, currentC.id])]

        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [oldA, oldB],
            groups: [BurstGroup(id: 1, fileIDs: [oldA.id, oldB.id])],
            results: [],
            reviewStateSnapshots: [BurstReviewStateSnapshot(signature: signature, state: .decisionApplied)],
        )

        let states = viewModel.cachedReviewStates(from: snapshot)

        #expect(states.isEmpty)
    }

    @Test
    func `cancelled burst analysis cannot apply a late cache result`() async {
        let gate = BurstCacheLoadGate()
        let cacheRepository = TestBurstAnalysisCacheRepository(
            load: { _, _, _, _, _ in await gate.load() },
        )
        let viewModel = RawCullViewModel(
            similarityService: CancellationDistanceSimilarityService(
                probe: SimilarityDistanceCancellationProbe(),
            ),
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: cacheRepository,
        )
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [BurstGroup(id: 0, fileIDs: [first.id, second.id])],
            results: [],
            reviewStateSnapshots: [],
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]
        let analysis = Task {
            await viewModel.restoreExistingFullCatalogBurstAnalysis()
        }
        await gate.waitUntilStarted()

        viewModel.cancelAndResetBurstAnalysis()
        await gate.resume(returning: snapshot)
        _ = await analysis.value

        #expect(viewModel.burstAnalysisTask == nil)
        #expect(!viewModel.burstAnalysisProgress.isRunning)
        #expect(viewModel.similarityModel.burstGroups.isEmpty)
        #expect(viewModel.burstAnalysisResults.isEmpty)
        #expect(viewModel.burstReviewStates.isEmpty)
    }

    @Test
    func `catalog cancellation resets all burst analysis state`() {
        let viewModel = RawCullViewModel()
        let file = makeCullingTestFile("A.ARW")
        viewModel.burstAnalysisProgress = BurstAnalysisProgress(step: .ranking)
        viewModel.burstAnalysisResults = [1: makeCullingBurstResult(groupID: 1, files: [file])]
        viewModel.burstReviewStates = [1: .deferred]
        viewModel.burstReviewQueueFilter = .deferred
        viewModel.activeBurstComparisonGroupID = 1
        viewModel.lastBurstUndoEntry = BurstUndoEntry(groupID: 1, previousRatingsByFileName: [file.name: 0])
        viewModel.comparisonFileIDs = [file.id]

        viewModel.cancelCatalogLoad()

        #expect(!viewModel.burstAnalysisProgress.isRunning)
        #expect(viewModel.burstAnalysisResults.isEmpty)
        #expect(viewModel.burstReviewStates.isEmpty)
        #expect(viewModel.burstReviewQueueFilter == .all)
        #expect(viewModel.activeBurstComparisonGroupID == nil)
        #expect(viewModel.lastBurstUndoEntry == nil)
        #expect(viewModel.comparisonFileIDs.isEmpty)
    }

    @Test
    func `burst cache rejects a different similarity signature`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCullingTestFile("A.ARW"), makeCullingTestFile("B.ARW")]
        let originalSignature = makeBurstSimilaritySignature(sensitivity: 0.25)
        let snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: [],
            results: [],
            reviewStateSnapshots: [],
            similaritySignature: originalSignature,
        )

        await cache.save(snapshot, catalog: catalog)

        let matching = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: originalSignature,
        )
        let mismatching = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: makeBurstSimilaritySignature(sensitivity: 0.10),
        )

        #expect(matching != nil)
        #expect(mismatching == nil)
    }

    @Test
    func `restoring an existing full burst index never starts scoring or indexing`() async {
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let group = BurstGroup(id: 0, fileIDs: [first.id, second.id])
        var snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [group],
            results: [makeCullingBurstResult(groupID: group.id, files: [first, second])],
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = [:]
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first, second],
            artifacts: [:],
        )
        let viewModel = RawCullViewModel(
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: TestBurstAnalysisCacheRepository(
                load: { _, _, _, _, _ in snapshot },
            ),
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]

        let restored = await viewModel.restoreExistingFullCatalogBurstAnalysis()

        #expect(restored)
        #expect(viewModel.hasExistingFullCatalogBurstGroupIndex)
        #expect(viewModel.similarityModel.burstGroups == [group])
        #expect(!viewModel.sharpnessModel.isScoring)
        #expect(!viewModel.similarityModel.isIndexing)
        #expect(!viewModel.burstAnalysisProgress.isRunning)
    }

    @Test
    func `burst cache rejects groups produced by the previous timestamp algorithm`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullAlgorithmCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = [makeCullingTestFile("A.ARW"), makeCullingTestFile("B.ARW")]
        var snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: [],
            results: [],
            reviewStateSnapshots: [],
        )
        snapshot.algorithmVersion = BurstGroupingConfig.algorithmVersion - 1

        await cache.save(snapshot, catalog: catalog)

        let loaded = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: 512,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
        )

        #expect(loaded == nil)
    }

    @Test
    func `burst cache reports usage and clears every catalog snapshot`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullUsageCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        for index in 0 ..< 2 {
            let catalog = URL(fileURLWithPath: "/tmp/catalog-\(index)-\(UUID().uuidString)")
            let files = [makeCullingTestFile("\(index)-A.ARW"), makeCullingTestFile("\(index)-B.ARW")]
            let snapshot = makeBurstSnapshot(
                catalog: catalog,
                files: files,
                groups: [],
                results: [],
                reviewStateSnapshots: [],
            )
            await cache.save(snapshot, catalog: catalog)
        }

        let populatedUsage = await cache.getDiskCacheUsage()
        #expect(populatedUsage.fileCount == 2)
        #expect(populatedUsage.size > 0)

        await cache.clear()

        let clearedUsage = await cache.getDiskCacheUsage()
        #expect(clearedUsage.fileCount == 0)
        #expect(clearedUsage.size == 0)
    }

    @Test
    func `burst cache round trips a large snapshot off the main actor`() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RawCullLargeCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cache = BurstAnalysisCache(cacheDirectory: directory)
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let files = (0 ..< 500).map { index in
            makeCullingTestFile("cache-\(index).ARW")
        }
        let groups = stride(from: 0, to: files.count, by: 5).enumerated().map { groupID, start in
            BurstGroup(id: groupID, fileIDs: files[start ..< min(start + 5, files.count)].map(\.id))
        }
        var snapshot = makeBurstSnapshot(
            catalog: catalog,
            files: files,
            groups: groups,
            results: groups.map { group in
                makeCullingBurstResult(
                    groupID: group.id,
                    files: group.fileIDs.compactMap { id in files.first { $0.id == id } },
                )
            },
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = Dictionary(uniqueKeysWithValues: files.map { file in
            (
                file.id,
                makeSimilarityTestArtifact(
                    source: SimilarityScoringModel.source(for: file),
                    payload: Data(
                        repeating: UInt8(file.name.count % 255),
                        count: 256,
                    ),
                ),
            )
        })
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: files,
            artifacts: snapshot.embeddings,
        )
        snapshot.sharpnessScores = Dictionary(uniqueKeysWithValues: files.enumerated().map { index, file in
            (file.id, Float(index) / Float(files.count))
        })

        await cache.save(snapshot, catalog: catalog)
        let loaded = await cache.load(
            catalog: catalog,
            files: files,
            thumbnailMaxPixelSize: snapshot.thumbnailMaxPixelSize,
            sharpnessSignature: snapshot.sharpnessSignature,
            similaritySignature: snapshot.similaritySignature,
        )

        #expect(loaded == snapshot)
    }

    @Test
    func `review state persistence keeps completed analysis scope`() async throws {
        let catalog = ARWSourceCatalog(
            name: "Catalog",
            url: URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)"),
        )
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let group = BurstGroup(id: 0, fileIDs: [first.id, second.id])
        let result = makeCullingBurstResult(groupID: 0, files: [first, second])
        var snapshot = makeBurstSnapshot(
            catalog: catalog.url,
            files: [first, second],
            groups: [group],
            results: [result],
            reviewStateSnapshots: [],
        )
        snapshot.embeddings = [:]
        snapshot.similarityArtifactSetDigest = BurstAnalysisCache.artifactSetDigest(
            files: [first, second],
            artifacts: [:],
        )
        let recorder = BurstCacheSaveRecorder()
        let viewModel = RawCullViewModel(
            similarityService: SuspendingSimilarityService(
                probe: SimilarityEmbeddingSuspensionProbe(),
            ),
            similarityArtifactStore: makeIsolatedSimilarityArtifactStore(),
            burstAnalysisCacheRepository: TestBurstAnalysisCacheRepository(
                load: { _, _, _, _, _ in snapshot },
                save: { savedSnapshot, _ in
                    await recorder.record(savedSnapshot)
                },
            ),
        )

        viewModel.selectedSource = catalog
        viewModel.files = [first, second]
        viewModel.filteredFiles = [first, second]

        #expect(await viewModel.restoreExistingFullCatalogBurstAnalysis())
        viewModel.selectedFileIDs = [first.id]
        viewModel.filteredFiles = [first]
        viewModel.markBurstGroupReviewed(groupID: 0)

        let saved = try #require(await recorder.waitForSnapshot())
        #expect(saved.files.map(\.path) == [first.url.path, second.url.path])
        #expect(saved.groups == [group])
        #expect(saved.results.first?.fileIDs == [first.id, second.id])
    }

    @Test
    func `live regroup review state follows membership instead of group id`() throws {
        let viewModel = RawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let third = makeCullingTestFile("C.ARW")
        let originalSignature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )
        let saved: [BurstGroupSignature: BurstReviewState] = [
            originalSignature: .deferred
        ]

        let restored = viewModel.restoredBurstReviewStates(
            savedStatesBySignature: saved,
            groups: [
                BurstGroup(id: 7, fileIDs: [first.id, second.id]),
                BurstGroup(id: 0, fileIDs: [third.id])
            ],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored == [7: .deferred])
    }

    @Test
    func `live regroup drops state when reused group id has changed membership`() throws {
        let viewModel = RawCullViewModel()
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")
        let first = makeCullingTestFile("A.ARW")
        let second = makeCullingTestFile("B.ARW")
        let third = makeCullingTestFile("C.ARW")
        let originalSignature = try #require(
            BurstGroupSignature(files: [first, second], catalog: catalog),
        )

        let restored = viewModel.restoredBurstReviewStates(
            savedStatesBySignature: [originalSignature: .reviewed],
            groups: [BurstGroup(id: 0, fileIDs: [first.id, third.id])],
            files: [first, second, third],
            catalog: catalog,
        )

        #expect(restored.isEmpty)
    }
}

@MainActor
private final class TestBurstAnalysisCacheRepository: BurstAnalysisCacheRepository {
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

private actor BurstCacheLoadGate {
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

private actor BurstCacheSaveRecorder {
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

private func makeBurstSimilaritySignature(
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
private func makeBurstSnapshot(
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
