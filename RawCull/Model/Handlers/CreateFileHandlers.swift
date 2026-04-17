//
//  CreateFileHandlers.swift
//  RawCull
//
//  Created by Thomas Evensen on 23/01/2026.
//

import Foundation

struct CreateFileHandlers {
    func createFileHandlers(
        fileHandler: @escaping @MainActor @Sendable (Int) -> Void,
        maxfilesHandler: @escaping @MainActor @Sendable (Int) -> Void,
        estimatedTimeHandler: @escaping @MainActor @Sendable (Int) -> Void,
        memorypressurewarning: @escaping @MainActor @Sendable (Bool) -> Void,
        onExtractionNeeded: @escaping @MainActor @Sendable () -> Void,
    ) -> FileHandlers {
        FileHandlers(
            fileHandler: fileHandler,
            maxfilesHandler: maxfilesHandler,
            estimatedTimeHandler: estimatedTimeHandler,
            memorypressurewarning: memorypressurewarning,
            onExtractionNeeded: onExtractionNeeded,
        )
    }
}

struct FileHandlers {
    let fileHandler: @MainActor @Sendable (Int) -> Void
    let maxfilesHandler: @MainActor @Sendable (Int) -> Void
    let estimatedTimeHandler: @MainActor @Sendable (Int) -> Void // Estimated seconds to completion
    let memorypressurewarning: @MainActor @Sendable (Bool) -> Void
    let onExtractionNeeded: @MainActor @Sendable () -> Void
}
