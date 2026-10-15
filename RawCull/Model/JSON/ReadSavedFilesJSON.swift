//
//  ReadSavedFilesJSON.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

//
//  ReadLogRecordsJSON.swift
//  RsyncUI
//
//  Created by Thomas Evensen on 19/04/2021.
//

import DecodeEncodeGeneric
import Foundation
import OSLog

nonisolated struct SavedFilesReadFailure: Error, Equatable, Identifiable, Sendable {
    let url: URL
    let message: String

    var id: URL {
        url
    }
}

nonisolated enum SavedFilesReadResult: Sendable {
    case missing(URL)
    case loaded([SavedFiles])
    case failed(SavedFilesReadFailure)
}

nonisolated final class ReadSavedFilesJSON: Sendable {
    private let fileName = "savedfiles.json"
    private let savedFilesURL: URL?

    private var savePath: URL {
        if let savedFilesURL {
            return savedFilesURL
        }
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("RawCull", isDirectory: true)
        return appFolder.appendingPathComponent(fileName)
    }

    init(savedFilesURL: URL? = nil) {
        self.savedFilesURL = savedFilesURL
    }

    @concurrent
    func readInBackground() async -> SavedFilesReadResult {
        read()
    }

    func read() -> SavedFilesReadResult {
        guard FileManager.default.fileExists(atPath: savePath.path) else {
            return .missing(savePath)
        }

        let decodeimport = DecodeGeneric()
        do {
            let data = try
                decodeimport.decodeArray(DecodeSavedFiles.self, fromFile: savePath.path)

            Logger.process.debugMessageOnly("ReadSavedFilesJSON - read filerecords from permanent storage")
            return .loaded(data.map { element in
                SavedFiles(element)
            })
        } catch let err {
            Logger.process.error("ReadSavedFilesJSON: failed to decode saved files: \(err)")
            return .failed(SavedFilesReadFailure(url: savePath, message: err.localizedDescription))
        }
    }

    func readjsonfilesavedfiles() -> [SavedFiles]? {
        guard case let .loaded(savedFiles) = read() else { return nil }
        return savedFiles
    }

    static func archiveCorruptStore(at url: URL) throws -> URL {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let archiveURL = url.deletingLastPathComponent()
            .appendingPathComponent("savedfiles-corrupt-\(timestamp).json")
        try FileManager.default.moveItem(at: url, to: archiveURL)
        return archiveURL
    }

    deinit {
        Logger.process.debugMessageOnly("ReadSavedFilesJSON: DEINIT")
    }
}
