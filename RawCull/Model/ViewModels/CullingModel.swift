import Foundation
import Observation
import OSLog

@Observable
final class CullingModel {
    var savedFiles = [SavedFiles]()

    func loadSavedFiles() {
        if let readjson = ReadSavedFilesJSON().readjsonfilesavedfiles() {
            savedFiles = readjson
        }
    }

    func resetSavedFiles(in catalog: URL) {
        if let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) {
            savedFiles[index].filerecords = nil
            // Save updated
            WriteSavedFilesJSON(savedFiles)
        }
    }

    private func verifytoggleSelectionSavedFiles(in arwcatalog: URL, toggledfilename: String) -> Bool {
        if let index = savedFiles.firstIndex(where: { $0.catalog == arwcatalog }) {
            if savedFiles[index].filerecords == nil { return false
            } else {
                let verify = savedFiles[index].filerecords?.filter { $0.fileName == toggledfilename }
                if verify?.isEmpty == false {
                    // Existing photo, remove photo
                    return true
                }
            }
        }
        return false
    }

    func toggleSelectionSavedFiles(in fileurl: URL?, toggledfilename: String) {
        if let fileurl {
            let arwcatalog = fileurl.deletingLastPathComponent()

            if verifytoggleSelectionSavedFiles(in: arwcatalog, toggledfilename: toggledfilename) {
                // Remove item
                if let index = savedFiles.firstIndex(where: { $0.catalog == arwcatalog }) {
                    savedFiles[index].filerecords?.removeAll { record in
                        record.fileName == toggledfilename
                    }
                }
            } else {
                // New item
                let newrecord = FileRecord(
                    fileName: toggledfilename,
                    dateTagged: Date().en_string_from_date(),
                    dateCopied: nil,
                    rating: 3
                )

                if savedFiles.isEmpty {
                    let savedfiles = SavedFiles(
                        catalog: arwcatalog,
                        dateStart: Date().en_string_from_date(),
                        filerecord: newrecord
                    )
                    savedFiles.append(savedfiles)
                } else {
                    // Check if arw catalog exists in data structure
                    if let index = savedFiles.firstIndex(where: { $0.catalog == arwcatalog }) {
                        if savedFiles[index].filerecords == nil {
                            savedFiles[index].filerecords = [newrecord]
                        } else {
                            savedFiles[index].filerecords?.append(newrecord)
                        }
                    } else {
                        // If not append a new one
                        let savedfiles = SavedFiles(
                            catalog: arwcatalog,
                            dateStart: Date().en_string_from_date(),
                            filerecord: newrecord
                        )
                        savedFiles.append(savedfiles)
                    }
                }
            }
            WriteSavedFilesJSON(savedFiles)
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
}
