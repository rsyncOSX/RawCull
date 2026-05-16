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
            savedFiles[index].filerecords = nil
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
