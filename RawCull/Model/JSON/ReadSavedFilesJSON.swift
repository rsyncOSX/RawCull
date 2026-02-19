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
    func readjsonfilesavedfiles() -> [SavedFiles]? {
        let fileName = "savedfiles.json"
        var savePath: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
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
                "ReadSavedFilesJSON: some ERROR encoding filerecords \(error)"
            )
        }
        return nil
    }

    deinit {
        Logger.process.debugMessageOnly("ReadSavedFilesJSON: DEINIT")
    }
}
