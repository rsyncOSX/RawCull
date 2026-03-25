//
//  ScanFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

//
//  ScanFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

import Foundation
import ImageIO
import OSLog

struct ExifMetadata: Hashable {
    let shutterSpeed: String?
    let focalLength: String?
    let aperture: String?
    let iso: String?
    let camera: String?
    let lensModel: String?
}

struct DecodeFocusPoints: Codable {
    let sourceFile: String
    let focusLocation: String

    enum CodingKeys: String, CodingKey {
        case sourceFile = "SourceFile"
        case focusLocation = "FocusLocation"
    }
}

actor ScanFiles {
    /// Store raw decoded data
    var decodedFocusPoints: [DecodeFocusPoints]?

    func scanFiles(
        url: URL,
        onProgress: (@MainActor @Sendable (_ count: Int) -> Void)? = nil,
    ) async -> [FileItem] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }

        var discoveredCount = 0
        Logger.process.debugThreadOnly("ScanFiles: func scanFiles()")

        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey
        ]

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
            )

            let result: [FileItem] = await withTaskGroup(of: FileItem?.self) { group in
                for fileURL in contents {
                    guard fileURL.pathExtension.lowercased() == SupportedFileType.arw.rawValue else { continue }
                    discoveredCount += 1
                    let progress = onProgress
                    let count = discoveredCount
                    Task { @MainActor in progress?(count) }
                    group.addTask {
                        let res = try? fileURL.resourceValues(forKeys: Set(keys))
                        let exifData = self.extractExifData(from: fileURL)
                        return FileItem(
                            url: fileURL,
                            name: res?.name ?? fileURL.lastPathComponent,
                            size: Int64(res?.fileSize ?? 0),
                            type: res?.contentType?.localizedDescription ?? "File",
                            dateModified: res?.contentModificationDate ?? Date(),
                            exifData: exifData,
                        )
                    }
                }
                var items: [FileItem] = []
                for await item in group {
                    if let item { items.append(item) }
                }
                return items
            }

            // Decode raw JSON — plain Codable struct, no @MainActor involved
            // Native Sony MakerNote parsing — no exiftool or focuspoints.json needed.
            // Falls back to focuspoints.json if native extraction yields nothing
            // (e.g. non-A1 files or files captured before the feature was added).
            decodedFocusPoints = extractNativeFocusPoints(from: result)
                ?? decodeFocusPointsJSON(from: url)

            return result
        } catch {
            Logger.process.warning("Scan Error: \(error)")
            return []
        }
    }

    /// Extracts focus location from each ARW file's Sony MakerNote directly.
    /// Returns `nil` if no files yielded a result so the JSON fallback can take over.
    private func extractNativeFocusPoints(from items: [FileItem]) -> [DecodeFocusPoints]? {
        let parsed = items.compactMap { item -> DecodeFocusPoints? in
            guard let location = SonyMakerNoteParser.focusLocation(from: item.url) else { return nil }
            // sourceFile must equal file.name — getFocusPoints() matches on filename only
            return DecodeFocusPoints(sourceFile: item.url.lastPathComponent, focusLocation: location)
        }
        return parsed.isEmpty ? nil : parsed
    }

    /// Synchronous — plain Data read + JSONDecoder, no actor-isolated types touched
    private func decodeFocusPointsJSON(from url: URL) -> [DecodeFocusPoints]? {
        let fileURL = url.appendingPathComponent("focuspoints.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([DecodeFocusPoints].self, from: data)
            Logger.process.debugThreadOnly("decodeFocusPointsJSON - read \(decoded.count) records")
            return decoded
        } catch {
            // Logger.process.errorMessageOnly("decodeFocusPointsJSON: ERROR \(error)")
            return nil
        }
    }

    @concurrent
    nonisolated func sortFiles(
        _ files: [FileItem],
        by sortOrder: [some SortComparator<FileItem>],
        searchText: String,
    ) async -> [FileItem] {
        Logger.process.debugThreadOnly("func sortFiles()")
        let sorted = files.sorted(using: sortOrder)
        if searchText.isEmpty {
            return sorted
        } else {
            return sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    // MARK: - EXIF Extraction

    private nonisolated func extractExifData(from url: URL) -> ExifMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            return nil
        }

        return ExifMetadata(
            shutterSpeed: formatShutterSpeed(exifDict[kCGImagePropertyExifExposureTime]),
            focalLength: formatFocalLength(exifDict[kCGImagePropertyExifFocalLength]),
            aperture: formatAperture(exifDict[kCGImagePropertyExifFNumber]),
            iso: formatISO((exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first),
            camera: tiffDict[kCGImagePropertyTIFFModel] as? String,
            lensModel: exifDict[kCGImagePropertyExifLensModel] as? String,
        )
    }

    private nonisolated func formatShutterSpeed(_ value: Any?) -> String? {
        guard let speed = value as? NSNumber else { return nil }
        let speedValue = speed.doubleValue
        if speedValue >= 1 {
            return String(format: "%.1f\"", speedValue)
        } else {
            return String(format: "1/%.0f", 1 / speedValue)
        }
    }

    private nonisolated func formatFocalLength(_ value: Any?) -> String? {
        guard let focal = value as? NSNumber else { return nil }
        return String(format: "%.1fmm", focal.doubleValue)
    }

    private nonisolated func formatAperture(_ value: Any?) -> String? {
        guard let aperture = value as? NSNumber else { return nil }
        return String(format: "ƒ/%.1f", aperture.doubleValue)
    }

    nonisolated func formatISO(_ iso: Int?) -> String? {
        guard let iso else { return nil }
        return "ISO \(iso)"
    }
}
