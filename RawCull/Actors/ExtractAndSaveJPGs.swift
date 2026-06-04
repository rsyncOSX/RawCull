//
//  ExtractAndSaveJPGs.swift
//  RawCull
//
//  Created by Thomas Evensen on 26/01/2026.
//

import Foundation
import OSLog
import RawParserKit

actor ExtractAndSaveJPGs {
    // Track the current preload task so we can cancel it

    private var extractJPEGSTask: Task<Int, Never>?
    private var successCount = 0

    private var fileHandlers: FileHandlers?

    // Timing tracking for estimated completion
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0
    private var estimationStartIndex = 10 // After 10 items, we can estimate

    private var filteredFilesURLs: [URL]?

    /// Used in time remaining
    private var lastItemTime: Date?

    init(sortedfiles: [FileItem]) {
        if !sortedfiles.isEmpty {
            filteredFilesURLs = sortedfiles.map(\.url)
        }
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    @discardableResult
    func extractAndSavejpgs() async -> Int {
        cancelExtractJPGSTask()

        if let filteredFilesURLs {
            let task = Task {
                successCount = 0
                processingTimes = []
                // let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
                totalFilesToProcess = filteredFilesURLs.count

                await fileHandlers?.maxfilesHandler(filteredFilesURLs.count)

                return await withTaskGroup(of: Void.self) { group in
                    let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

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
                    return successCount
                }
            }

            extractJPEGSTask = task
            return await task.value
        }

        return 0
    }

    private func processSingleExtraction(_ url: URL) async {
        if Task.isCancelled { return } // ← NEW

        guard let format = RawFormatRegistry.format(for: url) else { return }
        if let cgImage = await format.extractFullJPEG(from: url, fullSize: false) {
            if Task.isCancelled { return } // ← NEW: critical one

            guard let jpegData = SaveJPGImage.jpegData(from: cgImage) else { return }

            await SaveJPGImage().save(jpegData, originalURL: url)

            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(itemsProcessed: newCount)
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
