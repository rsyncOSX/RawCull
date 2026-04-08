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

    @discardableResult
    init(_ savedfiles: [SavedFiles]?) async {
        if let savedfiles {
            Logger.process.debugThreadOnly("WriteSavedFilesJSON INIT")
            await encodeJSONData(savedfiles)
        }
    }

    deinit {
        Logger.process.debugMessageOnly("WriteSavedFilesJSON DEINIT")
    }
}
