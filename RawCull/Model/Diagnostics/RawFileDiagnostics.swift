import Foundation
import ImageIO
import RawParserKit

@MainActor
enum RawFileDiagnostics {
    static func log(for file: FileItem) -> String {
        var logger = RawFileDiagnosticLogger()
        logger.line("RAW FILE DIAGNOSTICS")
        logger.line("name: \(file.name)")
        logger.line("path: \(file.url.path)")
        logger.line("extension: \(file.url.pathExtension.lowercased())")
        logger.line("sizeBytes: \(file.size)")
        logger.line("sizeFormatted: \(file.formattedSize)")
        logger.line("dateModified: \(Self.dateFormatter.string(from: file.dateModified))")

        if FileManager.default.fileExists(atPath: file.url.path) {
            logger.line("fileExists: yes")
            if !FileManager.default.isReadableFile(atPath: file.url.path) {
                logger.error("file is not readable")
            }
        } else {
            logger.error("file does not exist at path")
        }

        guard let format = RawFormatRegistry.format(for: file.url) else {
            logger.error("unsupported RAW extension")
            return logger.output
        }

        logger.line("format: \(formatName(format))")
        logExif(file.exifData, to: &logger)
        logImageIO(for: file.url, using: format, to: &logger)
        logParserDiagnostics(for: file.url, using: format, to: &logger)
        return logger.output
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func formatName(_ format: any RawFormat.Type) -> String {
        switch format {
        case is SonyRawFormat.Type:
            "Sony ARW"

        case is NikonRawFormat.Type:
            "Nikon NEF"

        default:
            String(describing: format)
        }
    }

    private static func logExif(_ exif: ExifMetadata?, to logger: inout RawFileDiagnosticLogger) {
        logger.line("")
        logger.line("SCAN METADATA")
        guard let exif else {
            logger.error("no scanned EXIF metadata stored on selected file")
            return
        }

        logger.line("camera: \(exif.camera ?? "nil")")
        logger.line("lens: \(exif.lensModel ?? "nil")")
        logger.line("shutterSpeed: \(exif.shutterSpeed ?? "nil")")
        logger.line("aperture: \(exif.aperture ?? "nil")")
        logger.line("apertureValue: \(string(exif.apertureValue))")
        logger.line("iso: \(exif.iso ?? "nil")")
        logger.line("isoValue: \(string(exif.isoValue))")
        logger.line("focalLength: \(exif.focalLength ?? "nil")")
        logger.line("pixelWidth: \(string(exif.pixelWidth))")
        logger.line("pixelHeight: \(string(exif.pixelHeight))")
        logger.line("rawFileType: \(exif.rawFileType ?? "nil")")
        logger.line("rawSizeClass: \(exif.rawSizeClass ?? "nil")")
    }

    private static func logImageIO(
        for url: URL,
        using format: any RawFormat.Type,
        to logger: inout RawFileDiagnosticLogger,
    ) {
        logger.line("")
        logger.line("IMAGEIO")

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            logger.error("ImageIO could not create image source")
            return
        }

        let count = CGImageSourceGetCount(source)
        logger.line("sourceCreated: yes")
        logger.line("imageCount: \(count)")

        for index in 0 ..< count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
                logger.error("ImageIO properties unavailable for index \(index)")
                continue
            }

            let width = intValue(properties[kCGImagePropertyPixelWidth])
                ?? nestedIntValue(properties, dictionary: kCGImagePropertyTIFFDictionary, key: kCGImagePropertyPixelWidth)
                ?? nestedIntValue(properties, dictionary: kCGImagePropertyExifDictionary, key: kCGImagePropertyExifPixelXDimension)
            let height = intValue(properties[kCGImagePropertyPixelHeight])
                ?? nestedIntValue(properties, dictionary: kCGImagePropertyTIFFDictionary, key: kCGImagePropertyPixelHeight)
                ?? nestedIntValue(properties, dictionary: kCGImagePropertyExifDictionary, key: kCGImagePropertyExifPixelYDimension)
            let hasJFIF = (properties[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
            let compression = nestedIntValue(properties, dictionary: kCGImagePropertyTIFFDictionary, key: kCGImagePropertyTIFFCompression)
            let compressionLabel = compression.map { format.rawFileTypeString(compressionCode: $0) } ?? "nil"

            logger.line("index \(index): width=\(string(width)) height=\(string(height)) hasJFIF=\(hasJFIF) compression=\(string(compression)) compressionLabel=\(compressionLabel)")
        }
    }

    private static func logParserDiagnostics(
        for url: URL,
        using format: any RawFormat.Type,
        to logger: inout RawFileDiagnosticLogger,
    ) {
        logger.line("")
        logger.line("PARSER TRACE")

        switch format {
        case is SonyRawFormat.Type:
            let jpeg = SonyMakerNoteParser.embeddedJPEGLocationsDiagnostics(from: url)
            logger.line("parser: Sony embedded JPEG locations")
            logger.lines(jpeg.trace)
            let locations = jpeg.value ?? .init()
            logLocation("sony.thumbnail", locations.thumbnail, to: &logger)
            logLocation("sony.preview", locations.preview, to: &logger)
            logLocation("sony.fullJPEG", locations.fullJPEG, to: &logger)
            if let failure = jpeg.failure { logger.error("Sony embedded JPEG parser: \(failure)") }

            let focus = SonyMakerNoteParser.focusLocationDiagnostics(from: url)
            logger.line("")
            logger.line("parser: Sony AF focus location")
            logger.lines(focus.trace)
            if let value = focus.value {
                logger.line("focusLocation: \(value)")
            } else {
                logger.error("Sony AF focus parser: \(focus.failure ?? "unknown failure")")
                logger.line("focusLocation: not found")
            }

        case is NikonRawFormat.Type:
            let jpeg = NikonMakerNoteParser.embeddedJPEGLocationsDiagnostics(from: url)
            logger.line("parser: Nikon embedded JPEG locations")
            logger.lines(jpeg.trace)
            let locations = jpeg.value ?? .init()
            logLocation("nikon.preview", locations.preview, to: &logger)
            logLocation("nikon.ifd1JPEG", locations.ifd1JPEG, to: &logger)
            if let failure = jpeg.failure { logger.error("Nikon embedded JPEG parser: \(failure)") }

            let focus = NikonMakerNoteParser.focusLocationDiagnostics(from: url)
            logger.line("")
            logger.line("parser: Nikon AF focus location")
            logger.lines(focus.trace)
            if let value = focus.value {
                logger.line("focusLocation: \(value)")
            } else {
                logger.error("Nikon AF focus parser: \(focus.failure ?? "unknown failure")")
                logger.line("focusLocation: not found")
            }

        default:
            logger.error("no embedded JPEG locator registered for \(formatName(format))")
        }
    }

    private static func logLocation(
        _ label: String,
        _ location: EmbeddedJPEGLocations.Location?,
        to logger: inout RawFileDiagnosticLogger,
    ) {
        guard let location else {
            logger.line("\(label): nil")
            return
        }
        logger.line("\(label): offset=\(location.offset) hex=0x\(String(location.offset, radix: 16, uppercase: true)) length=\(location.length)")
    }

    private static func logLocation(
        _ label: String,
        _ location: NEFEmbeddedJPEGLocations.Location?,
        to logger: inout RawFileDiagnosticLogger,
    ) {
        guard let location else {
            logger.line("\(label): nil")
            return
        }
        logger.line("\(label): offset=\(location.offset) hex=0x\(String(location.offset, radix: 16, uppercase: true)) length=\(location.length)")
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func nestedIntValue(
        _ properties: [CFString: Any],
        dictionary: CFString,
        key: CFString,
    ) -> Int? {
        guard let nested = properties[dictionary] as? [CFString: Any] else { return nil }
        return intValue(nested[key])
    }

    private static func string(_ value: Int?) -> String {
        value.map { "\($0)" } ?? "nil"
    }

    private static func string(_ value: Double?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
}

private struct RawFileDiagnosticLogger {
    private var lines: [String] = []

    var output: String {
        lines.joined(separator: "\n")
    }

    mutating func line(_ value: String) {
        lines.append(value)
    }

    mutating func lines(_ values: [String]) {
        lines.append(contentsOf: values)
    }

    mutating func error(_ value: String) {
        lines.append("ERROR: \(value)")
    }
}
