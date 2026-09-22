//
//  ScanFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

import Foundation
import OSLog
import RawCullCore
import RawParserKit

struct DecodeFocusPoints: Codable {
    let sourceFile: String
    let focusLocation: String

    enum CodingKeys: String, CodingKey {
        case sourceFile = "SourceFile"
        case focusLocation = "FocusLocation"
    }
}

enum FileItemSortField: Sendable {
    case name
    case dateModified
    case size
}

enum FileItemSortDirection: Sendable {
    case ascending
    case descending
}

struct FileItemSortDescriptor: Equatable, Sendable {
    var field: FileItemSortField
    var direction: FileItemSortDirection

    init(
        field: FileItemSortField = .name,
        direction: FileItemSortDirection = .ascending,
    ) {
        self.field = field
        self.direction = direction
    }

    nonisolated func sorted(_ files: [FileItem]) -> [FileItem] {
        files.enumerated().sorted { lhs, rhs in
            let comparison = compare(lhs.element, rhs.element)
            guard comparison != .orderedSame else {
                // Keep equal values in their input order instead of relying on
                // the standard library sort implementation to be stable.
                return lhs.offset < rhs.offset
            }
            switch direction {
            case .ascending:
                return comparison == .orderedAscending

            case .descending:
                return comparison == .orderedDescending
            }
        }.map(\.element)
    }

    private nonisolated func compare(_ lhs: FileItem, _ rhs: FileItem) -> ComparisonResult {
        switch field {
        case .name:
            return lhs.name.localizedStandardCompare(rhs.name)

        case .dateModified:
            return lhs.dateModified.compare(rhs.dateModified)

        case .size:
            if lhs.size < rhs.size {
                return .orderedAscending
            }
            if lhs.size > rhs.size {
                return .orderedDescending
            }
            return .orderedSame
        }
    }
}

actor ScanFiles {
    /// Store raw decoded data
    var decodedFocusPoints: [DecodeFocusPoints]?
    private let rawLoader: any RawImageLoading

    init(rawLoader: any RawImageLoading = RawParserKitImageLoader.shared) {
        Logger.process.debugMessageOnly("ScanFiles.init()")
        self.rawLoader = rawLoader
    }

    func scanFiles(
        url: URL,
        onProgress: (@MainActor @Sendable (_ count: Int) -> Void)? = nil,
    ) async -> [FileItem] {
        Logger.process.debugMessageOnly("ScanFiles.scanFiles()")
        let didStartSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if didStartSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var discoveredCount = 0
        // Logger.process.debugThreadOnly("ScanFiles: func scanFiles()")

        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey
        ]

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
            )

            // Single-pass: extract EXIF and Sony MakerNote focus point in the same task per file,
            // eliminating the second file-open pass that extractNativeFocusPoints() previously required.
            let rawLoader = rawLoader
            let pairs: [(FileItem, DecodeFocusPoints?)] = await withTaskGroup(
                of: (FileItem, DecodeFocusPoints?)?.self,
            ) { group in
                for fileURL in contents {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    guard RawFormatRegistry.format(for: fileURL) != nil else { continue }
                    discoveredCount += 1
                    let progress = onProgress
                    let count = discoveredCount
                    Task { @MainActor in progress?(count) }
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        let res = try? fileURL.resourceValues(forKeys: Set(keys))
                        let metadata = await rawLoader.fileMetadata(for: fileURL)
                        let focusStr = metadata?.focusLocation
                        let fileItem = FileItem(
                            url: fileURL,
                            name: res?.name ?? fileURL.lastPathComponent,
                            size: Int64(res?.fileSize ?? 0),
                            dateModified: res?.contentModificationDate ?? Date(),
                            captureDate: metadata?.captureDate,
                            captureTimeZoneOffsetSeconds: metadata?.captureTimeZoneOffsetSeconds,
                            exifData: metadata?.exifMetadata,
                            afFocusNormalized: metadata?.focusPoint,
                        )
                        let focusPoint: DecodeFocusPoints? = focusStr.map {
                            DecodeFocusPoints(sourceFile: fileURL.lastPathComponent, focusLocation: $0)
                        }
                        return (fileItem, focusPoint)
                    }
                }
                var collected: [(FileItem, DecodeFocusPoints?)] = []
                for await pair in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    if let pair {
                        collected.append(pair)
                    }
                }
                return collected
            }

            guard !Task.isCancelled else { return [] }

            let result = pairs.map(\.0)
            let nativePoints = pairs.compactMap(\.1)
            // Falls back to focuspoints.json if native MakerNote extraction yielded nothing
            // (e.g. non-A1 files or files captured before the feature was added).
            decodedFocusPoints = nativePoints.isEmpty ? await decodeFocusPointsJSON(from: url) : nativePoints

            return result
        } catch {
            // Logger.process.warning("Scan Error: \(error)")
            return []
        }
    }

    /// Reads focuspoints.json from the catalog directory. File I/O is offloaded to a
    /// background thread to avoid blocking the ScanFiles actor.
    private func decodeFocusPointsJSON(from url: URL) async -> [DecodeFocusPoints]? {
        Logger.process.debugMessageOnly("ScanFiles.decodeFocusPointsJSON()")
        let fileURL = url.appendingPathComponent("focuspoints.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try await Task.detached(priority: .utility) {
                try Data(contentsOf: fileURL)
            }.value
            return try JSONDecoder().decode([DecodeFocusPoints].self, from: data)
        } catch {
            return nil
        }
    }

    @concurrent
    nonisolated static func sortFiles(
        _ files: [FileItem],
        by sortOrder: FileItemSortDescriptor,
        searchText: String,
    ) async -> [FileItem] {
        Logger.process.debugMessageOnly("ScanFiles.sortFiles()")
        let sorted = sortOrder.sorted(files)
        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
}
