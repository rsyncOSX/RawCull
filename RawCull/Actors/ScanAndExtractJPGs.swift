//
//  ScanAndExtractJPGs.swift
//  RawCull
//

import CoreGraphics
import Foundation
import OSLog
import RawParserKit

actor ScanAndExtractJPGs {
    private var extractTask: Task<Int, Never>?
    private var successCount = 0
    private var fileHandlers: FileHandlers?

    private var processingTimes: [TimeInterval] = []
    private var totalFilesToProcess = 0
    private var lastItemTime: Date?

    private let urls: [URL]
    private let fullSizeCache: FullSizeJPGDiskCache

    private static let minimumSamplesBeforeEstimation = 10

    init(urls: [URL], fullSizeCache: FullSizeJPGDiskCache? = nil) {
        self.urls = urls
        self.fullSizeCache = fullSizeCache ?? SharedMemoryCache.shared.fullSizeJPGDiskCache
    }

    func setFileHandlers(_ fileHandlers: FileHandlers) {
        self.fileHandlers = fileHandlers
    }

    func cancelExtraction() {
        extractTask?.cancel()
        extractTask = nil
        Logger.process.debugMessageOnly("ScanAndExtractJPGs: cancelled")
    }

    @discardableResult
    func extractCatalogJPGs() async -> Int {
        cancelExtraction()

        let task = Task<Int, Never> {
            successCount = 0
            processingTimes = []
            lastItemTime = nil
            totalFilesToProcess = urls.count

            await fileHandlers?.maxfilesHandler(urls.count)

            return await withTaskGroup(of: Void.self) { group in
                let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

                for (index, url) in urls.enumerated() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }

                    if index >= maxConcurrent {
                        await group.next()
                    }

                    group.addTask {
                        await self.processSingleFile(url)
                    }
                }

                await group.waitForAll()
                return successCount
            }
        }

        extractTask = task
        return await task.value
    }

    private func processSingleFile(_ url: URL) async {
        if Task.isCancelled { return }

        if await fullSizeCache.contains(for: url) {
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        guard let format = RawFormatRegistry.format(for: url) else {
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        if Task.isCancelled { return }

        let orientedPreview = await Task.detached(priority: .userInitiated) {
            OrientationNormalizedImageLoader.loadSonyEmbeddedPreview(from: url)
        }.value
        let extracted: CGImage? = if let orientedPreview {
            orientedPreview
        } else {
            if let image = await format.extractFullJPEG(from: url, fullSize: false) {
                OrientationNormalizedImageLoader.applyingSourceOrientation(to: image, from: url) ?? image
            } else {
                nil
            }
        }

        guard let extracted else {
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        if Task.isCancelled { return }

        guard let jpegData = FullSizeJPGDiskCache.jpegData(from: extracted) else {
            let newCount = incrementAndGetCount()
            notifyFileHandler(newCount)
            updateEstimatedTime(itemsProcessed: newCount)
            return
        }

        await fullSizeCache.save(jpegData, for: url)

        let newCount = incrementAndGetCount()
        notifyFileHandler(newCount)
        updateEstimatedTime(itemsProcessed: newCount)
    }

    private func notifyFileHandler(_ count: Int) {
        let handler = fileHandlers?.fileHandler
        Task { @MainActor in handler?(count) }
    }

    private func updateEstimatedTime(itemsProcessed: Int) {
        let now = Date()

        if let lastTime = lastItemTime {
            processingTimes.append(now.timeIntervalSince(lastTime))
        }
        lastItemTime = now

        if itemsProcessed >= Self.minimumSamplesBeforeEstimation, !processingTimes.isEmpty {
            let recentTimes = processingTimes.suffix(min(10, processingTimes.count))
            let avgSecondsPerCompletion = recentTimes.reduce(0, +) / Double(recentTimes.count)
            let remainingItems = totalFilesToProcess - itemsProcessed
            let estimatedSeconds = Int(avgSecondsPerCompletion * Double(remainingItems))
            let handler = fileHandlers?.estimatedTimeHandler
            Task { @MainActor in handler?(estimatedSeconds) }
        }
    }

    private func incrementAndGetCount() -> Int {
        successCount += 1
        return successCount
    }
}
