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

    private func processSingleExtraction(_ url: URL, itemIndex: Int) async {
        let startTime = Date()

        if let cgImage = await ExtractEmbeddedPreview().extractEmbeddedPreview(
            from: url
        ) {
            await ExtractEmbeddedPreview().save(image: cgImage, originalURL: url)

            let newCount = incrementAndGetCount()
            await fileHandlers?.fileHandler(newCount)
            await updateEstimatedTime(for: startTime, itemIndex: itemIndex, itemsProcessed: newCount)
        }
    }

    private func updateEstimatedTime(for startTime: Date, itemIndex _: Int, itemsProcessed: Int) async {
        let elapsed = Date().timeIntervalSince(startTime)
        processingTimes.append(elapsed)

        // Once we have at least 10 measurements, calculate estimate
        if itemsProcessed >= estimationStartIndex, !processingTimes.isEmpty {
            let avgTimePerItem = processingTimes.reduce(0, +) / Double(processingTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgTimePerItem * Double(remainingItems))

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
