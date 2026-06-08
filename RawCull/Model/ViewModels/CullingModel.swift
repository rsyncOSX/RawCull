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
                scoringSignature: result.scoringSignature,
                scoringFileSize: result.fileSize,
                scoringModificationDate: result.modificationDate,
            )
        }
        scheduleSave()
    }

    func upsertBurstWinnerOverride(_ override: BurstWinnerOverride, in catalog: URL) {
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
