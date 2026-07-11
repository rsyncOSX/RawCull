//
//  ExtractAndSaveJPGs.swift
//  RawCull
//
//  Created by Thomas Evensen on 26/01/2026.
//

import CoreGraphics
import Foundation
import OSLog
import RawParserKit

nonisolated enum ExtractJPGExportMode: String, CaseIterable, Identifiable, Sendable {
    case embeddedJPG
    case demosaicedRAW

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .embeddedJPG: "Embedded JPG"
        case .demosaicedRAW: "Demosaiced RAW"
        }
    }
}

actor ExtractAndSaveJPGs {
    // Track the current preload task so we can cancel it

    private var extractJPEGSTask: Task<JPGExportResult, Never>?
    private var successCount = 0

    private var fileHandlers: FileHandlers?

    // Timing tracking for estimated completion
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0
    private var estimationStartIndex = 10 // After 10 items, we can estimate

    private var filteredFilesURLs: [URL]?
    private let destinationCatalogURL: URL?
    private let exportMode: ExtractJPGExportMode
    private let previewLoader: any FullSizePreviewLoading
    private let saveHandler: @Sendable (Data, URL, URL, ExtractJPGExportMode) async throws -> Void
    private var failures: [JPGExportFailure] = []

    /// Used in time remaining
    private var lastItemTime: Date?

    init(
        files: [FileItem],
        destinationCatalogURL: URL,
        exportMode: ExtractJPGExportMode,
        previewLoader: any FullSizePreviewLoading = FullSizePreviewLoader.shared,
        saveHandler: @escaping @Sendable (Data, URL, URL, ExtractJPGExportMode) async throws -> Void = {
            data, source, destination, mode in
            try await SaveJPGImage().save(
                data,
                originalURL: source,
                destinationCatalogURL: destination,
                exportMode: mode,
            )
        },
    ) {
        self.destinationCatalogURL = destinationCatalogURL
        self.exportMode = exportMode
        self.previewLoader = previewLoader
        self.saveHandler = saveHandler
        if !files.isEmpty {
            filteredFilesURLs = files.map(\.url)
        }
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    @discardableResult
    func extractAndSavejpgs() async -> JPGExportResult {
        cancelExtractJPGSTask()

        if let filteredFilesURLs {
            let task = Task {
                successCount = 0
                failures = []
                processingTimes = []
                // let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
                totalFilesToProcess = filteredFilesURLs.count

                await fileHandlers?.maxfilesHandler(filteredFilesURLs.count)

                return await withTaskGroup(of: Void.self) { group in
                    let maxConcurrent = RawImageLoadingConcurrency.batchExtractionLimit

                    for (index, url) in filteredFilesURLs.enumerated() {
                        if Task.isCancelled {
                            group.cancelAll()
                            break
                        }

                        if index >= maxConcurrent {
                            await group.next()
                        }

                        group.addTask {
                            await self.processSingleExtraction(url)
                        }
                    }

                    await group.waitForAll()
                    return JPGExportResult(succeeded: successCount, failures: failures)
                }
            }

            extractJPEGSTask = task
            return await task.value
        }

        return JPGExportResult(succeeded: 0, failures: [])
    }

    private func processSingleExtraction(_ url: URL) async {
        if Task.isCancelled { return } // ← NEW

        switch exportMode {
        case .embeddedJPG:
            guard let cgImage = await embeddedJPEGImage(from: url) else { return }
            if Task.isCancelled { return } // ← NEW: critical one

            guard let jpegData = SaveJPGImage.jpegData(from: cgImage) else { return }

            guard await save(jpegData, originalURL: url) else { return }

        case .demosaicedRAW:
            guard let jpegData = try? await SonyRawFormat.createFullSizeJPEG(from: url, quality: 1.0) else { return }
            if Task.isCancelled { return }

            guard await save(jpegData, originalURL: url) else { return }
        }

        let newCount = incrementAndGetCount()
        await fileHandlers?.fileHandler(newCount)
        await updateEstimatedTime(itemsProcessed: newCount)
    }

    private func embeddedJPEGImage(from url: URL) async -> CGImage? {
        await previewLoader.loadEmbeddedPreview(for: url)
    }

    private func save(_ jpegData: Data, originalURL: URL) async -> Bool {
        guard let destinationCatalogURL else { return false }
        do {
            try await saveHandler(jpegData, originalURL, destinationCatalogURL, exportMode)
            return true
        } catch {
            failures.append(JPGExportFailure(fileName: originalURL.lastPathComponent, message: error.localizedDescription))
            return false
        }
    }

    private func updateEstimatedTime(itemsProcessed: Int) async {
        let now = Date()

        if let lastTime = lastItemTime {
            let delta = now.timeIntervalSince(lastTime)
            processingTimes.append(delta)
        }
        lastItemTime = now

        if itemsProcessed >= estimationStartIndex, !processingTimes.isEmpty {
            let recentTimes = processingTimes.suffix(min(10, processingTimes.count))
            let avgSecondsPerCompletion = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgSecondsPerCompletion * Double(remainingItems))
            await fileHandlers?.estimatedTimeHandler(estimatedSeconds)
        }
    }

    func cancelExtractJPGSTask() {
        extractJPEGSTask?.cancel()
        extractJPEGSTask = nil
        Logger.process.debugMessageOnly("ExtractAndSaveJPGs: Preload Cancelled")
    }

    private func incrementAndGetCount() -> Int {
        successCount += 1
        return successCount
    }
}

nonisolated struct JPGExportFailure: Sendable, Equatable {
    let fileName: String
    let message: String
}

nonisolated struct JPGExportResult: Sendable, Equatable {
    let succeeded: Int
    let failures: [JPGExportFailure]
}
