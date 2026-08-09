import Foundation
import Observation
import OSLog
import RawCullCore

struct CullingScoringResult {
    let fileName: String
    let score: Float
    let saliencySubject: String?
    let scoringSignature: SharpnessScoringSignature?
    let fileSize: Int64?
    let modificationDate: Date?

    init(
        fileName: String,
        score: Float,
        saliencySubject: String?,
        scoringSignature: SharpnessScoringSignature? = nil,
        fileSize: Int64? = nil,
        modificationDate: Date? = nil,
    ) {
        self.fileName = fileName
        self.score = score
        self.saliencySubject = saliencySubject
        self.scoringSignature = scoringSignature
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

@Observable @MainActor
final class CullingModel {
    private(set) var savedFiles = [SavedFiles]()
    private(set) var persistenceError: String?
    private(set) var persistenceLoadFailure: SavedFilesReadFailure?
    private(set) var hasUnsavedChanges = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelayNanoseconds: UInt64
    @ObservationIgnored private let saveHandler: @Sendable ([SavedFiles]) async throws -> Void
    @ObservationIgnored private let loadHandler: @MainActor () -> SavedFilesReadResult
    @ObservationIgnored private var persistenceRevision: UInt64 = 0

    init(
        saveDelayNanoseconds: UInt64 = 350_000_000,
        saveHandler: @escaping @Sendable ([SavedFiles]) async throws -> Void = { savedFiles in
            try await WriteSavedFilesJSON.write(savedFiles)
        },
        loadHandler: @escaping @MainActor () -> SavedFilesReadResult = {
            ReadSavedFilesJSON().read()
        },
    ) {
        self.saveDelayNanoseconds = saveDelayNanoseconds
        self.saveHandler = saveHandler
        self.loadHandler = loadHandler
    }

    @discardableResult
    func loadSavedFiles() -> Bool {
        switch loadHandler() {
        case .missing:
            savedFiles = []
            persistenceLoadFailure = nil
            persistenceError = nil
            return true

        case let .loaded(loadedFiles):
            savedFiles = loadedFiles
            persistenceLoadFailure = nil
            persistenceError = nil
            return true

        case let .failed(failure):
            persistenceLoadFailure = failure
            persistenceError = "RawCull could not read saved culling data at \(failure.url.path). The file has been preserved and automatic changes are blocked. \(failure.message)"
            return false
        }
    }

    func resetSavedFiles(in catalog: URL) {
        guard canMutate else { return }
        if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            savedFiles[index].filerecords = []
            savedFiles[index].burstWinnerOverrides = []
            scheduleSave()
        }
    }

    func resetAllSavedFiles() {
        guard canMutate else { return }
        savedFiles.removeAll()
        scheduleSave()
    }

    func countSelectedFiles(in catalog: URL) -> Int {
        if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            if let filerecords = savedFiles[index].filerecords {
                return filerecords.count
            }
        }
        return 0
    }

    func isUnrated(photo: String, in catalog: URL) -> Bool {
        rating(for: photo, in: catalog) == nil
    }

    func rating(for photo: String, in catalog: URL) -> Int? {
        savedFiles
            .first(where: { $0.catalog == catalog })?
            .filerecords?
            .first(where: { $0.fileName == photo })?
            .rating
    }

    func updateRating(fileName: String, rating: Int, in catalog: URL) {
        updateRatings(fileNames: [fileName], rating: rating, in: catalog)
    }

    func updateRatings(fileNames: [String], rating: Int, in catalog: URL) {
        guard canMutate, !fileNames.isEmpty else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)

        for fileName in fileNames {
            upsertRecord(
                catalogIndex: catalogIndex,
                fileName: fileName,
                dateTagged: date,
                rating: rating,
            )
        }
        scheduleSave()
    }

    func applyRatings(_ ratingsByFileName: [String: Int], in catalog: URL) {
        guard canMutate, !ratingsByFileName.isEmpty else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)

        for (fileName, rating) in ratingsByFileName {
            upsertRecord(
                catalogIndex: catalogIndex,
                fileName: fileName,
                dateTagged: date,
                rating: rating,
            )
        }
        scheduleSave()
    }

    func applyRatingStates(_ ratingsByFileName: [String: Int?], in catalog: URL) {
        guard canMutate, !ratingsByFileName.isEmpty else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)

        for (fileName, rating) in ratingsByFileName {
            if let recordIndex = savedFiles[catalogIndex].filerecords?
                .firstIndex(where: { $0.fileName == fileName }) {
                savedFiles[catalogIndex].filerecords?[recordIndex].rating = rating
                savedFiles[catalogIndex].filerecords?[recordIndex].dateTagged = rating == nil ? nil : date
            } else if let rating {
                upsertRecord(
                    catalogIndex: catalogIndex,
                    fileName: fileName,
                    dateTagged: date,
                    rating: rating,
                )
            }
        }
        scheduleSave()
    }

    func mergeScoringResults(_ results: [CullingScoringResult], in catalog: URL) {
        guard canMutate, !results.isEmpty else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)

        for result in results {
            upsertRecord(
                catalogIndex: catalogIndex,
                fileName: result.fileName,
                sharpnessScore: result.score,
                saliencySubject: result.saliencySubject,
                updateSaliencySubject: true,
                scoringSignature: result.scoringSignature,
                scoringFileSize: result.fileSize,
                scoringModificationDate: result.modificationDate,
            )
        }
        scheduleSave()
    }

    // periphery:ignore
    func upsertBurstWinnerOverride(_ override: BurstWinnerOverride, in catalog: URL) {
        guard canMutate else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)
        let normalizedOverride = BurstWinnerOverride(
            id: override.id,
            winnerFileName: override.winnerFileName,
            memberFileNames: Self.canonicalMemberNames(override.memberFileNames),
        )
        let newMembership = normalizedOverride.memberFileNames

        if savedFiles[catalogIndex].burstWinnerOverrides == nil {
            savedFiles[catalogIndex].burstWinnerOverrides = []
        }

        savedFiles[catalogIndex].burstWinnerOverrides?.removeAll { existing in
            Self.canonicalMemberNames(existing.memberFileNames) == newMembership
        }
        savedFiles[catalogIndex].burstWinnerOverrides?.append(normalizedOverride)
        scheduleSave()
    }

    func burstWinnerOverrides(in catalog: URL) -> [BurstWinnerOverride] {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return [] }
        return savedFiles[index].burstWinnerOverrides ?? []
    }

    func overrideWinner(for groupFiles: [FileItem], in catalog: URL) -> BurstWinnerOverride? {
        let groupNames = Self.canonicalMemberNames(groupFiles.map(\.name))
        return burstWinnerOverrides(in: catalog)
            .last {
                Self.canonicalMemberNames($0.memberFileNames) == groupNames &&
                    groupNames.contains($0.winnerFileName)
            }
    }

    func pruneStaleBurstOverrides(validFileNames: Set<String>, in catalog: URL) {
        guard canMutate else { return }
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        let original = savedFiles[index].burstWinnerOverrides ?? []
        let pruned = original.filter {
            validFileNames.contains($0.winnerFileName) &&
                !$0.memberFileNames.isEmpty &&
                $0.memberFileNames.allSatisfy { validFileNames.contains($0) }
        }
        guard pruned.count != original.count else { return }
        savedFiles[index].burstWinnerOverrides = pruned
        scheduleSave()
    }

    nonisolated static func canonicalMemberNames(_ names: [String]) -> [String] {
        names
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private func scheduleSave() {
        persistenceRevision &+= 1
        let snapshot = savedFiles
        let revision = persistenceRevision
        let delay = saveDelayNanoseconds

        saveTask?.cancel()
        hasUnsavedChanges = true
        guard persistenceLoadFailure == nil else { return }
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            _ = await persist(snapshot, revision: revision)
        }
    }

    @discardableResult
    func retryPersistence() async -> Bool {
        if persistenceLoadFailure != nil {
            return loadSavedFiles()
        }
        saveTask?.cancel()
        saveTask = nil
        return await persist(savedFiles, revision: persistenceRevision)
    }

    @discardableResult
    func flushPersistence() async -> Bool {
        guard persistenceLoadFailure == nil else { return false }
        guard hasUnsavedChanges else { return true }
        saveTask?.cancel()
        saveTask = nil
        return await persist(savedFiles, revision: persistenceRevision)
    }

    @discardableResult
    func archiveCorruptStoreAndReset() async -> Bool {
        guard let failure = persistenceLoadFailure else { return true }
        do {
            _ = try ReadSavedFilesJSON.archiveCorruptStore(at: failure.url)
            savedFiles = []
            persistenceLoadFailure = nil
            persistenceError = nil
            persistenceRevision &+= 1
            hasUnsavedChanges = true
            return await persist(savedFiles, revision: persistenceRevision)
        } catch {
            persistenceError = "RawCull could not preserve the damaged saved-data file. \(error.localizedDescription)"
            return false
        }
    }

    func hasExplicitRatings(in catalog: URL) -> Bool {
        savedFiles
            .first(where: { $0.catalog == catalog })?
            .filerecords?
            .contains(where: { $0.rating != nil }) ?? false
    }

    private func persist(_ snapshot: [SavedFiles], revision: UInt64) async -> Bool {
        do {
            try await saveHandler(snapshot)
            if revision == persistenceRevision {
                hasUnsavedChanges = false
                persistenceError = nil
            }
            return true
        } catch {
            hasUnsavedChanges = true
            persistenceError = error.localizedDescription
            Logger.process.errorMessageOnly("CullingModel: failed to persist saved files: \(error)")
            return false
        }
    }

    private var canMutate: Bool {
        persistenceLoadFailure == nil
    }

    private func ensureCatalog(_ catalog: URL, dateStart: String?) -> Int {
        if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            if savedFiles[index].filerecords == nil {
                savedFiles[index].filerecords = []
            }
            return index
        }

        savedFiles.append(SavedFiles(
            catalog: catalog,
            dateStart: dateStart,
            filerecord: FileRecord(fileName: nil, dateTagged: nil, dateCopied: nil, rating: nil),
        ))
        let index = savedFiles.index(before: savedFiles.endIndex)
        savedFiles[index].filerecords = []
        return index
    }

    private func upsertRecord(
        catalogIndex: Int,
        fileName: String,
        dateTagged: String? = nil,
        rating: Int? = nil,
        sharpnessScore: Float? = nil,
        saliencySubject: String? = nil,
        updateSaliencySubject: Bool = false,
        scoringSignature: SharpnessScoringSignature? = nil,
        scoringFileSize: Int64? = nil,
        scoringModificationDate: Date? = nil,
    ) {
        if let recordIndex = savedFiles[catalogIndex].filerecords?.firstIndex(where: { $0.fileName == fileName }) {
            if let rating {
                savedFiles[catalogIndex].filerecords?[recordIndex].rating = rating
            }
            if let sharpnessScore {
                savedFiles[catalogIndex].filerecords?[recordIndex].sharpnessScore = sharpnessScore
            }
            if updateSaliencySubject {
                savedFiles[catalogIndex].filerecords?[recordIndex].saliencySubject = saliencySubject
            }
            if let scoringSignature {
                savedFiles[catalogIndex].filerecords?[recordIndex].sharpnessScoringSignature = scoringSignature
                savedFiles[catalogIndex].filerecords?[recordIndex].sharpnessFileSize = scoringFileSize
                savedFiles[catalogIndex].filerecords?[recordIndex].sharpnessModificationDate = scoringModificationDate
            }
            return
        }

        savedFiles[catalogIndex].filerecords?.append(FileRecord(
            fileName: fileName,
            dateTagged: dateTagged,
            dateCopied: nil,
            rating: rating,
            sharpnessScore: sharpnessScore,
            saliencySubject: saliencySubject,
            sharpnessScoringSignature: scoringSignature,
            sharpnessFileSize: scoringFileSize,
            sharpnessModificationDate: scoringModificationDate,
        ))
    }
}
