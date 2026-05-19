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

@MainActor
final class ReadSavedFilesJSON {
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

    func readjsonfilesavedfiles() -> [SavedFiles]? {
        guard FileManager.default.fileExists(atPath: savePath.path) else {
            return nil
        }

        let decodeimport = DecodeGeneric()
        do {
            let data = try
                decodeimport.decodeArray(DecodeSavedFiles.self, fromFile: savePath.path)

            Logger.process.debugMessageOnly("ReadSavedFilesJSON - read filerecords from permanent storage")
            return data.map { element in
                SavedFiles(element)
            }
        } catch let err {
            let error = err
            Logger.process.errorMessageOnly(
                "ReadSavedFilesJSON: some ERROR encoding filerecords \(error)",
            )
        }
        return nil
    }

    deinit {
        Logger.process.debugMessageOnly("ReadSavedFilesJSON: DEINIT")
    }
}
