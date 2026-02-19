//
//  extension+Thread+Logger.swift
//  RawCull
//
//  Created by Thomas Evensen on 20/01/2026.
//

import Foundation
import OSLog

public extension Thread {
    static var isMain: Bool {
        isMainThread
    }

    static var currentThread: Thread {
        Thread.current
    }

    nonisolated static func checkIsMainThread() -> Bool {
        Thread.isMainThread
    }
}

extension Logger {
    private nonisolated static let subsystem = Bundle.main.bundleIdentifier
    nonisolated static let process = Logger(subsystem: subsystem ?? "process", category: "process")

    func errorMessageOnly(_ message: String) {
        #if DEBUG
            error("\(message)")
        #endif
    }

    nonisolated func debugMessageOnly(_ message: String) {
        #if DEBUG
            debug("\(message)")
        #endif
    }

    nonisolated func debugThreadOnly(_ message: String) {
        #if DEBUG
            if Thread.checkIsMainThread() {
                debug("\(message) Running on main thread")
            } else {
                debug("\(message) NOT on main thread, currently on \(Thread.current)")
            }
        #endif
    }
}

extension Task where Success == Never, Failure == Never {
    static func sleep(seconds: Double) async throws {
        let duration = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: duration)
    }
}
