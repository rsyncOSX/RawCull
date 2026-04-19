import Foundation
import Observation
import OSLog

@Observable @MainActor
final class CullingModel {
    var savedFiles = [SavedFiles]()

    func loadSavedFiles() {
        if let readjson = ReadSavedFilesJSON().readjsonfilesavedfiles() {
            savedFiles = readjson
        }
    }

    func resetSavedFiles(in catalog: URL) {
        Task {
            if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
                savedFiles[index].filerecords = nil
                // Save updated
                await WriteSavedFilesJSON.write(savedFiles)
            }
        }
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
}
