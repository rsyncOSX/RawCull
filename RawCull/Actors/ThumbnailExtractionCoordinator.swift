//
//  ThumbnailExtractionCoordinator.swift
//  RawCull
//

import CoreGraphics
import Foundation

actor ThumbnailExtractionCoordinator {
    static let shared = ThumbnailExtractionCoordinator()

    struct Key: Hashable {
        let sourcePath: String
        let targetSize: Int
        let qualityCost: Int

        init(url: URL, targetSize: Int, qualityCost: Int) {
            if url.isFileURL {
                sourcePath = url.standardizedFileURL.path
            } else {
                sourcePath = url.standardized.absoluteString
            }
            self.targetSize = targetSize
            self.qualityCost = qualityCost
        }
    }

    private var inFlight: [Key: Task<CGImage, Error>] = [:]

    func extract(
        key: Key,
        operation: @Sendable @escaping () async throws -> CGImage,
    ) async throws -> CGImage {
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task(priority: .userInitiated) {
            try await operation()
        }
        inFlight[key] = task

        do {
            let image = try await task.value
            inFlight[key] = nil
            return image
        } catch {
            inFlight[key] = nil
            throw error
        }
    }
}
