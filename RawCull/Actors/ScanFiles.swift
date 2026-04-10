//
//  ScanFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

import Foundation
import ImageIO

// import OSLog

struct ExifMetadata: Hashable {
    let shutterSpeed: String?
    let focalLength: String?
    let aperture: String? // formatted display string, e.g. "ƒ/5.6"
    let apertureValue: Double? // raw f-number for filtering, e.g. 5.6
    let iso: String?
    let isoValue: Int? // raw integer ISO for computation (e.g. 6400)
    let camera: String?
    let lensModel: String?
    let rawFileType: String? // "Uncompressed" | "Compressed" | "Lossless Compressed"
    let rawSizeClass: String? // "L" | "M" | "S"
    let pixelWidth: Int?
    let pixelHeight: Int?
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
                of: (FileItem, DecodeFocusPoints?).self,
            ) { group in
                for fileURL in contents {
                    guard fileURL.pathExtension.lowercased() == SupportedFileType.arw.rawValue else { continue }
                    discoveredCount += 1
                    let progress = onProgress
                    let count = discoveredCount
                    Task { @MainActor in progress?(count) }
                    group.addTask {
                        let res = try? fileURL.resourceValues(forKeys: Set(keys))
                        let exifData = self.extractExifData(from: fileURL)
                        let fileItem = FileItem(
                            url: fileURL,
                            name: res?.name ?? fileURL.lastPathComponent,
                            size: Int64(res?.fileSize ?? 0),
                            dateModified: res?.contentModificationDate ?? Date(),
                            exifData: exifData,
                        )
                        let focusPoint: DecodeFocusPoints? = SonyMakerNoteParser.focusLocation(from: fileURL).map {
                            DecodeFocusPoints(sourceFile: fileURL.lastPathComponent, focusLocation: $0)
                        }
                        return (fileItem, focusPoint)
                    }
                }
                var collected: [(FileItem, DecodeFocusPoints?)] = []
                for await pair in group {
                    collected.append(pair)
                }
                return collected
            }

            let result = pairs.map(\.0)
            let nativePoints = pairs.compactMap(\.1)
            // Falls back to focuspoints.json if native MakerNote extraction yielded nothing
            // (e.g. non-A1 files or files captured before the feature was added).
            decodedFocusPoints = nativePoints.isEmpty ? decodeFocusPointsJSON(from: url) : nativePoints

            return result
        } catch {
            // Logger.process.warning("Scan Error: \(error)")
            return []
        }
    }

    /// Synchronous — plain Data read + JSONDecoder, no actor-isolated types touched
    private func decodeFocusPointsJSON(from url: URL) -> [DecodeFocusPoints]? {
        let fileURL = url.appendingPathComponent("focuspoints.json")
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([DecodeFocusPoints].self, from: data)
            // Logger.process.debugThreadOnly("decodeFocusPointsJSON - read \(decoded.count) records")
        } catch {
            // Logger.process.errorMessageOnly("decodeFocusPointsJSON: ERROR \(error)")
            return nil
        }
    }

    @concurrent
    nonisolated static func sortFiles(
        _ files: [FileItem],
        by sortOrder: [some SortComparator<FileItem>],
        searchText: String,
    ) async -> [FileItem] {
        // Logger.process.debugThreadOnly("func sortFiles()")
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

        let fNumber = exifDict[kCGImagePropertyExifFNumber] as? NSNumber
        let rawISO = (exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        // pixelWidth/Height are top-level properties, not inside kCGImagePropertyTIFFDictionary
        let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int
        let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        let compressionValue = tiffDict[kCGImagePropertyTIFFCompression] as? Int
        let cameraModel = tiffDict[kCGImagePropertyTIFFModel] as? String
        let rawSizeClass: String? = (pixelWidth != nil && pixelHeight != nil)
            ? sizeClass(width: pixelWidth!, height: pixelHeight!, camera: cameraModel ?? "")
            : nil
        return ExifMetadata(
            shutterSpeed: formatShutterSpeed(exifDict[kCGImagePropertyExifExposureTime]),
            focalLength: formatFocalLength(exifDict[kCGImagePropertyExifFocalLength]),
            aperture: formatAperture(fNumber),
            apertureValue: fNumber.map { $0.doubleValue },
            iso: formatISO(rawISO),
            isoValue: rawISO,
            camera: cameraModel,
            lensModel: exifDict[kCGImagePropertyExifLensModel] as? String,
            rawFileType: compressionValue.map { rawFileTypeString(from: $0) },
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

    /// Maps the TIFF compression tag to a human-readable Sony RAW type label.
    /// Newer bodies (A1, A7R V, A9 III…) write 6/7; older bodies write 32767/32770.
    /// Both generations use the same semantic meaning: lossy compressed vs lossless compressed.
    private nonisolated func rawFileTypeString(from value: Int) -> String {
        switch value {
        case 1: "Uncompressed"
        case 6: "Compressed" // newer Sony bodies (A1, A7R V…)
        case 7: "Lossless Compressed" // newer Sony bodies (A1, A7R V…)
        case 32767: "Compressed" // older Sony bodies
        case 32770: "Lossless Compressed" // older Sony bodies
        default: "Unknown (\(value))"
        }
    }

    /// Classifies pixel dimensions as L / M / S using per-body MP thresholds.
    /// Thresholds are derived from each camera's known resolution steps — e.g. the A1
    /// shoots L at ~50 MP, M at ~21 MP, and S at ~12 MP, so the M boundary sits at 18 MP.
    /// The fallback (25/10) covers unknown bodies generically.
    private nonisolated func sizeClass(width: Int, height: Int, camera: String) -> String {
        let mp = Double(width * height) / 1_000_000
        let upper = camera.uppercased()
        // (L threshold MP, M threshold MP) — classified as L if ≥ lThresh, M if ≥ mThresh, else S
        let (lThresh, mThresh): (Double, Double)
        if upper.contains("ILCE-7RM") { (lThresh, mThresh) = (50, 22) } // A7R IV/V: 61/26/15 MP
        else if upper.contains("ILCE-1") { (lThresh, mThresh) = (40, 18) } // A1/A1 II: 50/21/12 MP
        else if upper.contains("ILCE-9") { (lThresh, mThresh) = (20, 10) } // A9 III: 24/12/6 MP
        else if upper.contains("ILCE-7") { (lThresh, mThresh) = (28, 14) } // A7M5: 33/17/9 MP
        else { (lThresh, mThresh) = (25, 10) } // generic fallback
        if mp >= lThresh { return "L" }
        if mp >= mThresh { return "M" }
        return "S"
    }
}
