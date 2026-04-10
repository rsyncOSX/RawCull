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
    private let fileName = "savedfiles.json"
    private var savePath: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    /// Write saved files to persistent storage.
    static func write(_ savedFiles: [SavedFiles]?) async {
        guard let savedFiles else { return }
        await WriteSavedFilesJSON().performWrite(savedFiles)
    }

    private init() {}

    private func performWrite(_ savedFiles: [SavedFiles]) async {
        Logger.process.debugThreadOnly("WriteSavedFilesJSON write")
        await encodeJSONData(savedFiles)
    }

    private func writeJSONToPersistentStore(jsonData: Data?) async {
        if let jsonData {
            do {
                try jsonData.write(to: savePath, options: .atomic)
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
