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
    static func write(_ savedFiles: [SavedFiles]?, to savedFilesURL: URL? = nil) async throws {
        guard let savedFiles else { return }
        if let savedFilesURL {
            try await WriteSavedFilesJSON(savedFilesURL: savedFilesURL).performWrite(savedFiles)
        } else {
            try await shared.performWrite(savedFiles)
        }
    }

    private init(savedFilesURL: URL? = nil) {
        self.savedFilesURL = savedFilesURL
    }

    private func performWrite(_ savedFiles: [SavedFiles]) async throws {
        Logger.process.debugThreadOnly("WriteSavedFilesJSON write")
        let encodejsondata = EncodeGeneric()
        let encodedData = try encodejsondata.encode(savedFiles)
        let fileURL = savePath
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try encodedData.write(to: fileURL, options: .atomic)
    }
}
