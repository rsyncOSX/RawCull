//
//  ReadFocusPointsJSON.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import Foundation
import OSLog
import DecodeEncodeGeneric

@MainActor
final class ReadFocusPointsJSON {
    
    func readFocusPointsJSON() -> [FocusPointsModel]? {
        let fileName = "focuspoints.json"
        var savePath: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(fileName)
        }

        let decodeimport = DecodeGeneric()
        do {
            let data = try
                decodeimport.decodeArray(DecodeFocusPoints.self, fromFile: savePath.path)

            Logger.process.debugMessageOnly("ReadFocusPointsJSON - read filerecords from permanent storage")
            return data.map { element in
                let sourceFile = element.sourceFile
                let focusLocation = element.focusLocation
                return FocusPointsModel(sourceFile: sourceFile, focusLocations: [focusLocation])
            }
        } catch let err {
            let error = err
            Logger.process.errorMessageOnly(
                "ReadFocusPointsJSON: some ERROR encoding filerecords \(error)"
            )
        }
        return nil
    }


    deinit {
        Logger.process.debugMessageOnly("ReadFocusPointsJSON: DEINIT")
    }
}

struct DecodeFocusPoints: Codable {
    let sourceFile: String
    let focusLocation: String

    /// Mapping the JSON keys to Swift property names
    enum CodingKeys: String, CodingKey {
        case sourceFile = "SourceFile"
        case focusLocation = "FocusLocation"
    }
}
