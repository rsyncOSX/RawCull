//
//  SavedFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

//
//  LogRecords.swift
//  RsyncUI
//

import Foundation

/*
 › [0] RawCull.SavedFiles
 > [1] ARWPhoto Culler.SavedFiles v [2] RawCull.SavedFiles
 > id = 76FCFADE-B5BA-43E2-89F2-41EFC793C6DC: Foundation.UUID
 › catalog = "file:///Users/thomas/Pictures_raw/2025/24_jun_2025_hornugle/": Foundation...
 › dateStart = "16 Feb 2026 10:59": String?
 v filerecords = 12 values: [RawCull.FileRecord]?

 v [O] RawCull.FileRecord
 › id = 9BAE68A9-F80B-4FA4-A548-327ABE9B1233: Foundation.UUID
 > fileName = "_DSC4627.ARW": String?
 › dateTagged = "16 Feb 2026 11:14": String?
 dateCopied = nil: String?
 › rating = 3: Int?

 • [1] ARWPhoto Culler.FileRecord
 > id = 8B2140C6-5C41-49CC-A587-15324AA4F18A: Foundation.UUID
 > fileName = "_DSC4678.ARW": String?
 › dateTagged = "16 Feb 2026 11:14": String?
 dateCopied = nil: String?
 › rating = 3: Int?

 > [2] RawCull.FileRecord
 › [3] ARWPhoto Culler.FileRecord
 > [4] ARWPhoto Culler.FileRecord
 > [5] RawCull.FileRecord
 > [6] RawCull.FileRecord
 > [7] ARWPhoto Culler.FileRecord
 > [8] RawCull.FileRecord
 > [9] RawCull.FileRecord
 > [10] RawCull.FileRecord
 > [11] RawCull.FileRecord
 ....
 */

struct SavedFiles: Identifiable, Codable {
    var id = UUID()
    var catalog: URL?
    var dateStart: String?
    var filerecords: [FileRecord]?

    /// Used when reading JSON data from store
    init(_ data: DecodeSavedFiles) {
        catalog = data.catalog
        dateStart = data.dateStart ?? ""
        filerecords = data.filerecords?.map { record in
            FileRecord(
                fileName: record.fileName,
                dateTagged: record.dateTagged,
                dateCopied: record.dateCopied,
                rating: record.rating
            )
        }
    }

    /// Create a new record
    init(catalog: URL, dateStart: String?, filerecord: FileRecord) {
        self.catalog = catalog
        self.dateStart = dateStart
        self.filerecords = [filerecord]
    }
}

extension SavedFiles: Hashable, Equatable {
    static func == (lhs: SavedFiles, rhs: SavedFiles) -> Bool {
        lhs.dateStart == rhs.dateStart &&
            lhs.catalog == rhs.catalog
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateStart)
        hasher.combine(catalog)
    }
}

struct FileRecord: Identifiable, Codable {
    var id = UUID()
    var fileName: String?
    var dateTagged: String?
    var dateCopied: String?
    var rating: Int?
    var date: Date {
        dateTagged?.en_date_from_string() ?? Date()
    }
}

extension FileRecord: Hashable, Equatable {
    static func == (lhs: FileRecord, rhs: FileRecord) -> Bool {
        lhs.fileName == rhs.fileName &&
            lhs.dateTagged == rhs.dateTagged &&
            lhs.dateCopied == rhs.dateCopied &&
            lhs.rating == rhs.rating
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(fileName)
        hasher.combine(dateTagged)
        hasher.combine(dateCopied)
        hasher.combine(rating)
    }
}
