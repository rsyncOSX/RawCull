//
//  ReadFocusPointsJSON.swift
//  RawCull
//
//  Created by Thomas Evensen on 02/03/2026.
//

import DecodeEncodeGeneric
import Foundation
import OSLog

@MainActor
final class ReadFocusPointsJSON {
    var urlCatalog: URL?

    func readFocusPointsJSON() -> [FocusPointsModel]? {
        let fileName = "focuspoints.json"

        // Construct the full URL to the JSON file by appending the filename to the catalog URL
        guard let urlCatalog = urlCatalog else { return nil }
        let fileURL = urlCatalog.appendingPathComponent(fileName)

        // Check that the file actually exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            Logger.process.errorMessageOnly("ReadFocusPointsJSON: file not found at \(fileURL.path)")
            return nil
        }

        let decodeimport = DecodeGeneric()
        do {
            let data = try decodeimport.decodeArray(
                DecodeFocusPoints.self,
                fromFile: fileURL.path // <-- use the constructed fileURL
            )

            Logger.process.debugMessageOnly("ReadFocusPointsJSON - read filerecords from permanent storage")
            return data.map { element in
                FocusPointsModel(
                    sourceFile: element.sourceFile,
                    focusLocations: [element.focusLocation]
                )
            }
        } catch {
            Logger.process.errorMessageOnly(
                "ReadFocusPointsJSON: some ERROR encoding filerecords \(error)"
            )
        }
        return nil
    }

    init(urlCatalog: URL? = nil) {
        self.urlCatalog = urlCatalog
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
