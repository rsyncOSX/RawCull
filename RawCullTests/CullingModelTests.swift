import CoreGraphics
import Foundation
import PhotoAIContracts
import PhotoAnalysisKit
@testable import RawCull
import RawCullCore
import Synchronization
import Testing

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
    func `corrupt load blocks mutations and preserves in-memory state`() async {
        let url = URL(fileURLWithPath: "/tmp/savedfiles-\(UUID().uuidString).json")
        let failure = SavedFilesReadFailure(url: url, message: "Malformed JSON")
        let model = CullingModel(
            saveDelayNanoseconds: 0,
            saveHandler: { _ in },
            loadHandler: { .failed(failure) },
        )
        let catalog = URL(fileURLWithPath: "/tmp/catalog-\(UUID().uuidString)")

        #expect(await !model.loadSavedFiles())
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
            candidate.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: candidate)),
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
        probe.releaseDistance()
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
            candidate.id: makeSimilarityTestArtifact(source: SimilarityScoringModel.source(for: candidate)),
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
        probe.releaseDistance()
        await ranking.value

        #expect(probe.didObserveCancellation())
        #expect(model.anchorFileID == previousAnchorID)
        #expect(model.distances == previousDistances)
        #expect(model.sortBySimilarity == false)
    }

    @Test
    func `find similar indexes a fresh catalog before ranking`() async {
        let viewModel = makeRawCullViewModel(
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
            makeCullingTestFile("B.ARW"),
        ]
        let changed = [
            makeCullingTestFile("A.ARW"),
            makeCullingTestFile("X.ARW"),
            makeCullingTestFile("Y.ARW"),
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
