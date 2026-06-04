//
//  ScanFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

import Foundation
import ImageIO
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
            let pairs: [(FileItem, DecodeFocusPoints?)] = await withTaskGroup(
                of: (FileItem, DecodeFocusPoints?)?.self,
            ) { group in
                for fileURL in contents {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    guard let format = RawFormatRegistry.format(for: fileURL) else { continue }
                    discoveredCount += 1
                    let progress = onProgress
                    let count = discoveredCount
                    Task { @MainActor in progress?(count) }
                    group.addTask {
                        guard !Task.isCancelled else { return nil }
                        let res = try? fileURL.resourceValues(forKeys: Set(keys))
                        let exifData = self.extractExifData(from: fileURL, format: format)
                        let focusStr = format.focusLocation(from: fileURL)
                        let fileItem = FileItem(
                            url: fileURL,
                            name: res?.name ?? fileURL.lastPathComponent,
                            size: Int64(res?.fileSize ?? 0),
                            dateModified: res?.contentModificationDate ?? Date(),
                            exifData: exifData,
                            afFocusNormalized: focusStr.flatMap { FocusPointParser.normalizedPoint(from: $0) },
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

    private nonisolated func extractExifData(from url: URL, format: any RawFormat.Type) -> ExifMetadata? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else {
            return nil
        }

        let fNumber = exifDict[kCGImagePropertyExifFNumber] as? NSNumber
        let rawISO = (exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        // pixelWidth/Height are top-level properties, not inside kCGImagePropertyTIFFDictionary
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        let compressionValue = tiffDict[kCGImagePropertyTIFFCompression] as? Int
        let cameraModel = tiffDict[kCGImagePropertyTIFFModel] as? String
        let rawSizeClass: String? = if let pixelWidth, let pixelHeight {
            sizeClass(width: pixelWidth, height: pixelHeight, camera: cameraModel ?? "", format: format)
        } else {
            nil
        }
        return ExifMetadata(
            shutterSpeed: formatShutterSpeed(exifDict[kCGImagePropertyExifExposureTime]),
            focalLength: formatFocalLength(exifDict[kCGImagePropertyExifFocalLength]),
            aperture: formatAperture(fNumber),
            apertureValue: fNumber.map { $0.doubleValue },
            iso: formatISO(rawISO),
            isoValue: rawISO,
            camera: cameraModel,
            lensModel: exifDict[kCGImagePropertyExifLensModel] as? String,
            rawFileType: compressionValue.map { format.rawFileTypeString(compressionCode: $0) },
            rawSizeClass: rawSizeClass,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
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

    /// Classifies pixel dimensions as L / M / S using per-body MP thresholds
    /// looked up from the resolved `RawFormat`. Each conformer owns its own
    /// table of body-specific thresholds.
    private nonisolated func sizeClass(
        width: Int,
        height: Int,
        camera: String,
        format: any RawFormat.Type,
    ) -> String {
        let mp = Double(width * height) / 1_000_000
        let (lThresh, mThresh) = format.sizeClassThresholds(camera: camera)
        if mp >= lThresh { return "L" }
        if mp >= mThresh { return "M" }
        return "S"
    }
}
