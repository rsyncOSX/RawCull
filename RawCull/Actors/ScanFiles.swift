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
    func scanFiles(url: URL) async -> [FileItem] {
        // Essential for Sandbox apps
        guard url.startAccessingSecurityScopedResource() else { return [] }
        defer { url.stopAccessingSecurityScopedResource() }

        Logger.process.debugThreadOnly("func scanFiles()")

        let keys: [URLResourceKey] = [
            .nameKey,
            .fileSizeKey,
            .contentTypeKey,
            .contentModificationDateKey
        ]
        let manager = FileManager.default

        do {
            let contents = try manager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )

            return contents.compactMap { fileURL -> FileItem? in
                // Check for .arw extension (case-insensitive)
                guard fileURL.pathExtension.lowercased() == SupportedFileType.arw.rawValue else { return nil }

                let res = try? fileURL.resourceValues(forKeys: Set(keys))
                let exifData = extractExifData(from: fileURL)

                return FileItem(
                    url: fileURL,
                    name: res?.name ?? fileURL.lastPathComponent,
                    size: Int64(res?.fileSize ?? 0),
                    type: res?.contentType?.localizedDescription ?? "File",
                    dateModified: res?.contentModificationDate ?? Date(),
                    exifData: exifData
                )
            }
        } catch {
            Logger.process.warning("Scan Error: \(error)")
        }

        return []
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
