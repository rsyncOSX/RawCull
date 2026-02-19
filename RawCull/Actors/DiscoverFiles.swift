//
//  DiscoverFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 26/01/2026.
//

import AppKit
import Foundation
import OSLog

actor DiscoverFiles {
    let supported: Set<String> = [SupportedFileType.arw.rawValue]

    func discoverFiles(at catalogURL: URL, recursive: Bool) async -> [URL] {
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default

            var urls: [URL] = []

            guard let enumerator = fileManager.enumerator(
                at: catalogURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: recursive ? [] : [.skipsSubdirectoryDescendants]
            ) else { return urls }

            while let fileURL = enumerator.nextObject() as? URL {
                if self.supported.contains(fileURL.pathExtension.lowercased()) {
                    urls.append(fileURL)
                }
            }
            return urls
        }.value
    }
}
