//
//  ExtractAndSaveJPGs.swift
//  RawCull
//
//  Created by Thomas Evensen on 26/01/2026.
//

import Foundation
import OSLog

actor ExtractAndSaveJPGs {
    // Track the current preload task so we can cancel it

    private var extractJPEGSTask: Task<Int, Never>?
    private var successCount = 0

    private var fileHandlers: FileHandlers?

    // Timing tracking for estimated completion
    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0
    private var estimationStartIndex = 10 // After 10 items, we can estimate

    /// Used in time remaining
    private var lastItemTime: Date?
    private var lastEstimatedSeconds: Int?

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    @discardableResult
    func extractAndSaveAlljpgs(from catalogURL: URL, fullSize _: Bool = false) async -> Int {
        cancelExtractJPGSTask()

        let task = Task {
            successCount = 0
            processingTimes = []
            let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
            totalFilesToProcess = urls.count

            await fileHandlers?.maxfilesHandler(urls.count)

            return await withThrowingTaskGroup(of: Void.self) { group in
                let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2 // Be a bit more aggressive

                for (index, url) in urls.enumerated() {
                    // Check for cancellation at the start of every loop
                    if Task.isCancelled {
                        group.cancelAll() // FIX #2: Stop all running tasks
                        break
                    }

                    if index >= maxConcurrent {
                        try? await group.next()
                    }

                    group.addTask {
                        await self.processSingleExtraction(url, itemIndex: index)
                    }
                }

                // Wait for remaining tasks to finish (or be cancelled)
                try? await group.waitForAll()
                return successCount
            }
        }

        extractJPEGSTask = task
        return await task.value
    }

    private func processSingleExtraction(_ url: URL, itemIndex _: Int) async {
        let startTime = Date()

        if let cgImage = await enumextractEmbeddedPreview.extractEmbeddedPreview(
            from: url,
            nonBlocking: true
        ) {
            await SaveJPGImage().save(image: cgImage, originalURL: url)

            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(for: startTime, itemsProcessed: newCount)
        }
    }

    private func updateEstimatedTime(for _: Date, itemsProcessed: Int) async {
        let now = Date()

        if let lastTime = lastItemTime {
            let delta = now.timeIntervalSince(lastTime)
            processingTimes.append(delta)
        }
        lastItemTime = now

        if itemsProcessed >= estimationStartIndex, !processingTimes.isEmpty {
            let recentTimes = processingTimes.suffix(min(10, processingTimes.count))
            let avgTimePerItem = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgTimePerItem * Double(remainingItems))

            // Only update if the new estimate is lower than the current one
            if let current = lastEstimatedSeconds, estimatedSeconds > current {
                return
            }

            lastEstimatedSeconds = estimatedSeconds
            await fileHandlers?.estimatedTimeHandler(estimatedSeconds)
        }
    }

    private func cancelExtractJPGSTask() {
        extractJPEGSTask?.cancel()
        extractJPEGSTask = nil
        Logger.process.debugMessageOnly("ExtractAndSaveAlljpgs: Preload Cancelled")
    }

    private func incrementAndGetCount() -> Int {
        successCount += 1
        return successCount
    }
}
