//
//  ReadFocusPointsJSON.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import DecodeEncodeGeneric
import Foundation
import OSLog

/// Stateless value type — no actor isolation needed.
/// readFocusPointsJSON() is async so callers don't block their own actor.
struct ReadFocusPointsJSON {
    let urlCatalog: URL

    func readFocusPointsJSON() async -> [FocusPointsModel]? {
        let fileURL = urlCatalog.appendingPathComponent("focuspoints.json")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.process.errorMessageOnly("ReadFocusPointsJSON: file not found at \(fileURL.path)")
            return nil
        }

        let decodeimport = DecodeGeneric()
        do {
            let data = try decodeimport.decodeArray(
                DecodeFocusPoints.self,
                fromFile: fileURL.path
            )
            Logger.process.debugMessageOnly("ReadFocusPointsJSON - read \(data.count) focus point records")
            return data.map { element in
                FocusPointsModel(
                    sourceFile: element.sourceFile,
                    focusLocations: [element.focusLocation]
                )
            }
        } catch {
            Logger.process.errorMessageOnly("ReadFocusPointsJSON: decode ERROR \(error)")
            return nil
        }
    }
}

struct DecodeFocusPoints: Codable {
    let sourceFile: String
    let focusLocation: String

    enum CodingKeys: String, CodingKey {
        case sourceFile = "SourceFile"
        case focusLocation = "FocusLocation"
    }
}
