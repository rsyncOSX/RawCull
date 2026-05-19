//
//  WriteSavedFilesJSON.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

import DecodeEncodeGeneric
import Foundation
import OSLog

actor WriteSavedFilesJSON {
    private static let shared = WriteSavedFilesJSON()

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

    /// Write saved files to persistent storage.
    static func write(_ savedFiles: [SavedFiles]?, to savedFilesURL: URL? = nil) async {
        guard let savedFiles else { return }
        if let savedFilesURL {
            await WriteSavedFilesJSON(savedFilesURL: savedFilesURL).performWrite(savedFiles)
        } else {
            await shared.performWrite(savedFiles)
        }
    }

    private init(savedFilesURL: URL? = nil) {
        self.savedFilesURL = savedFilesURL
    }

    private func performWrite(_ savedFiles: [SavedFiles]) async {
        Logger.process.debugThreadOnly("WriteSavedFilesJSON write")
        await encodeJSONData(savedFiles)
    }

    private func writeJSONToPersistentStore(jsonData: Data?) async {
        if let jsonData {
            do {
                let fileURL = savePath
                try FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: nil,
                )
                try jsonData.write(to: fileURL, options: .atomic)
            } catch let err {
                let error = err
                await Logger.process.errorMessageOnly(
                    "WriteSavedFilesJSON: some ERROR writing filerecords to permanent storage \(error)",
                )
            }
        }
    }

    private func encodeJSONData(_ savedFiles: [SavedFiles]) async {
        let encodejsondata = EncodeGeneric()
        do {
            let encodeddata = try encodejsondata.encode(savedFiles)
            await writeJSONToPersistentStore(jsonData: encodeddata)
        } catch let err {
            let error = err
            await Logger.process.errorMessageOnly(
                "WriteSavedFilesJSON: some ERROR encoding filerecords \(error)",
            )
        }
    }
}
