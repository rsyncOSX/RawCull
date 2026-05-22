import Foundation
import Observation
import OSLog

struct CullingScoringResult {
    let fileName: String
    let score: Float
    let saliencySubject: String?
}

@Observable @MainActor
final class CullingModel {
    private(set) var savedFiles = [SavedFiles]()

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let saveDelayNanoseconds: UInt64
    @ObservationIgnored private let saveHandler: @Sendable ([SavedFiles]) async -> Void

    init(
        saveDelayNanoseconds: UInt64 = 350_000_000,
        saveHandler: @escaping @Sendable ([SavedFiles]) async -> Void = { savedFiles in
            await WriteSavedFilesJSON.write(savedFiles)
        },
    ) {
        self.saveDelayNanoseconds = saveDelayNanoseconds
        self.saveHandler = saveHandler
    }

    func loadSavedFiles() {
        if let readjson = ReadSavedFilesJSON().readjsonfilesavedfiles() {
            savedFiles = readjson
        }
    }

    func resetSavedFiles(in catalog: URL) {
        if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            savedFiles[index].filerecords = []
            savedFiles[index].burstWinnerOverrides = []
            savedFiles[index].reviewQueueStates = []
            scheduleSave()
        }
    }

    func resetAllSavedFiles() {
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
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else {
            return false
        }
        return savedFiles[index].filerecords?.contains { $0.fileName == photo } ?? false
    }

    func updateRating(fileName: String, rating: Int, in catalog: URL) {
        updateRatings(fileNames: [fileName], rating: rating, in: catalog)
    }

    func updateRatings(fileNames: [String], rating: Int, in catalog: URL) {
        guard !fileNames.isEmpty else { return }
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
        guard !ratingsByFileName.isEmpty else { return }
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

    func mergeScoringResults(_ results: [CullingScoringResult], in catalog: URL) {
        guard !results.isEmpty else { return }
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)

        for result in results {
            upsertRecord(
                catalogIndex: catalogIndex,
                fileName: result.fileName,
                sharpnessScore: result.score,
                saliencySubject: result.saliencySubject,
                updateSaliencySubject: true,
            )
        }
        scheduleSave()
    }

    func upsertBurstWinnerOverride(_ override: BurstWinnerOverride, in catalog: URL) {
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)
        let newMembership = Set(override.memberFileNames)

        if savedFiles[catalogIndex].burstWinnerOverrides == nil {
            savedFiles[catalogIndex].burstWinnerOverrides = []
        }

        savedFiles[catalogIndex].burstWinnerOverrides?.removeAll { existing in
            existing.winnerFileName == override.winnerFileName ||
                Set(existing.memberFileNames) == newMembership
        }
        savedFiles[catalogIndex].burstWinnerOverrides?.append(override)
        scheduleSave()
    }

    func burstWinnerOverrides(in catalog: URL) -> [BurstWinnerOverride] {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return [] }
        return savedFiles[index].burstWinnerOverrides ?? []
    }

    func overrideWinner(for groupFiles: [FileItem], in catalog: URL) -> BurstWinnerOverride? {
        let groupNames = Set(groupFiles.map(\.name))
        return burstWinnerOverrides(in: catalog)
            .last { groupNames.contains($0.winnerFileName) }
    }

    func removeBurstWinnerOverride(id: UUID, in catalog: URL) {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }),
              savedFiles[index].burstWinnerOverrides?.contains(where: { $0.id == id }) == true
        else { return }
        savedFiles[index].burstWinnerOverrides?.removeAll { $0.id == id }
        scheduleSave()
    }

    func pruneStaleBurstOverrides(validFileNames: Set<String>, in catalog: URL) {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        let original = savedFiles[index].burstWinnerOverrides ?? []
        let pruned = original.filter { validFileNames.contains($0.winnerFileName) }
        guard pruned.count != original.count else { return }
        savedFiles[index].burstWinnerOverrides = pruned
        scheduleSave()
    }

    func reviewQueueStates(in catalog: URL) -> [ReviewQueueItemState] {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return [] }
        return savedFiles[index].reviewQueueStates ?? []
    }

    func updateReviewQueueState(_ state: ReviewQueueItemState, in catalog: URL) {
        let date = Date().en_string_from_date()
        let catalogIndex = ensureCatalog(catalog, dateStart: date)
        if savedFiles[catalogIndex].reviewQueueStates == nil {
            savedFiles[catalogIndex].reviewQueueStates = []
        }
        if let stateIndex = savedFiles[catalogIndex].reviewQueueStates?.firstIndex(where: { $0.fingerprint == state.fingerprint }) {
            savedFiles[catalogIndex].reviewQueueStates?[stateIndex] = state
        } else {
            savedFiles[catalogIndex].reviewQueueStates?.append(state)
        }
        scheduleSave()
    }

    func reopenReviewQueueState(fingerprint: String, in catalog: URL) {
        updateReviewQueueState(
            ReviewQueueItemState(
                fingerprint: fingerprint,
                resolutionState: .open,
                resolvedAt: nil,
            ),
            in: catalog,
        )
    }

    func clearReviewQueueStates(in catalog: URL) {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        savedFiles[index].reviewQueueStates = []
        scheduleSave()
    }

    func pruneReviewQueueStates(validFingerprints: Set<String>, in catalog: URL) {
        guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return }
        let original = savedFiles[index].reviewQueueStates ?? []
        let pruned = original.filter { validFingerprints.contains($0.fingerprint) }
        guard pruned.count != original.count else { return }
        savedFiles[index].reviewQueueStates = pruned
        scheduleSave()
    }

    private func scheduleSave() {
        let snapshot = savedFiles
        let delay = saveDelayNanoseconds
        let saveHandler = saveHandler

        saveTask?.cancel()
        saveTask = Task {
            do {
                try await Task.sleep(nanoseconds: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await saveHandler(snapshot)
        }
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
            return
        }

        savedFiles[catalogIndex].filerecords?.append(FileRecord(
            fileName: fileName,
            dateTagged: dateTagged,
            dateCopied: nil,
            rating: rating,
            sharpnessScore: sharpnessScore,
            saliencySubject: saliencySubject,
        ))
    }
}
