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

actor ScanFiles {
    /// Populated after scanFiles() completes if focuspoints.json exists in the catalog.
    /// exiftool -Sony:FocusLocation *.ARW -j >> focuspoints.json
    var focusPoints: [FocusPointsModel]?

    func scanFiles(
        url: URL,
        onProgress: (@MainActor @Sendable (_ count: Int) -> Void)? = nil
    ) async -> [FileItem] {
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }

        var discoveredCount = 0

        Logger.process.debugThreadOnly("func scanFiles()")

        let keys: [URLResourceKey] = [
            .nameKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey
        ]

        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )

            // 1. Scan and build FileItems concurrently
            let result: [FileItem] = await withTaskGroup(of: FileItem?.self) { group in
                for fileURL in contents {
                    guard fileURL.pathExtension.lowercased() == SupportedFileType.arw.rawValue else { continue }

                    discoveredCount += 1
                    await onProgress?(discoveredCount)

                    group.addTask {
                        let res = try? fileURL.resourceValues(forKeys: Set(keys))
                        let exifData = await self.extractExifData(from: fileURL)

                        return FileItem(
                            url: fileURL,
                            name: res?.name ?? fileURL.lastPathComponent,
                            size: Int64(res?.fileSize ?? 0),
                            type: res?.contentType?.localizedDescription ?? "File",
                            dateModified: res?.contentModificationDate ?? Date(),
                            exifData: exifData
                        )
                    }
                }

                var items: [FileItem] = []
                for await item in group {
                    if let item { items.append(item) }
                }
                return items
            }

            // 2. Read focus points AFTER the task group — we are back on the
            //    ScanFiles actor here, so mutating focusPoints is safe and
            //    no isolation warning is emitted.
            focusPoints = await ReadFocusPointsJSON(urlCatalog: url).readFocusPointsJSON()

            return result
        } catch {
            Logger.process.warning("Scan Error: \(error)")
            return []
        }
    }

    @concurrent
    nonisolated func sortFiles<C: SortComparator<FileItem>>(
        _ files: [FileItem],
        by sortOrder: [C],
        searchText: String
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

    private func extractExifData(from url: URL) -> ExifMetadata? {
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
            iso: formatISO(exifDict[kCGImagePropertyExifISOSpeedRatings]),
            camera: tiffDict[kCGImagePropertyTIFFModel] as? String,
            lensModel: exifDict[kCGImagePropertyExifLensModel] as? String
        )
    }

    private func formatShutterSpeed(_ value: Any?) -> String? {
        guard let speed = value as? NSNumber else { return nil }
        let speedValue = speed.doubleValue
        if speedValue >= 1 {
            return String(format: "%.1f\"", speedValue)
        } else {
            return String(format: "1/%.0f", 1 / speedValue)
        }
    }

    private func formatFocalLength(_ value: Any?) -> String? {
        guard let focal = value as? NSNumber else { return nil }
        return String(format: "%.1fmm", focal.doubleValue)
    }

    private func formatAperture(_ value: Any?) -> String? {
        guard let aperture = value as? NSNumber else { return nil }
        return String(format: "ƒ/%.1f", aperture.doubleValue)
    }

    private func formatISO(_ value: Any?) -> String? {
        guard let iso = value as? NSNumber else { return nil }
        return String(format: "ISO %.0f", iso.doubleValue)
    }
}
