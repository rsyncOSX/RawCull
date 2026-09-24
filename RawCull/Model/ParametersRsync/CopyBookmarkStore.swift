import Foundation
import OSLog

enum CopyBookmarkFailure: Error, Equatable {
    case missingDestination
    case invalidDestination
    case accessDenied
    case couldNotSave
}

/// Owns one successful security-scope acquisition until release or deinitialization.
@MainActor
final class CopyScopedAccess {
    let url: URL
    private let stopAccessing: (URL) -> Void
    private var isReleased = false

    init(url: URL, stopAccessing: @escaping (URL) -> Void) {
        self.url = url
        self.stopAccessing = stopAccessing
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        stopAccessing(url)
    }

    isolated deinit {
        release()
    }
}

struct CopyBookmarkOperations {
    var makeBookmark: (URL) throws -> Data
    var resolveBookmark: (Data) throws -> (url: URL, isStale: Bool)
    var startAccessing: (URL) -> Bool
    var stopAccessing: (URL) -> Void

    static let live = CopyBookmarkOperations(
        makeBookmark: { try $0.bookmarkData(options: .withSecurityScope) },
        resolveBookmark: { data in
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale,
            )
            return (url, isStale)
        },
        startAccessing: { $0.startAccessingSecurityScopedResource() },
        stopAccessing: { $0.stopAccessingSecurityScopedResource() },
    )
}

@MainActor
final class CopyBookmarkStore {
    private enum Key: String {
        /// Preserve the existing preference key so saved destinations keep working.
        case destination = "destBookmark"
    }

    private let defaults: UserDefaults
    private let operations: CopyBookmarkOperations

    init(defaults: UserDefaults = .standard, operations: CopyBookmarkOperations = .live) {
        self.defaults = defaults
        self.operations = operations
    }

    func saveDestination(_ url: URL) throws {
        let access = try acquire(url)
        defer { access.release() }

        let data: Data
        do {
            data = try operations.makeBookmark(url)
        } catch {
            throw CopyBookmarkFailure.couldNotSave
        }
        defaults.set(data, forKey: Key.destination.rawValue)
    }

    func acquireSource(_ url: URL) throws -> CopyScopedAccess {
        try acquire(url)
    }

    func acquireDestination() throws -> CopyScopedAccess {
        guard let data = defaults.data(forKey: Key.destination.rawValue) else {
            throw CopyBookmarkFailure.missingDestination
        }

        let resolved: (url: URL, isStale: Bool)
        do {
            resolved = try operations.resolveBookmark(data)
        } catch {
            throw CopyBookmarkFailure.invalidDestination
        }

        let access = try acquire(resolved.url)
        if resolved.isStale {
            do {
                try defaults.set(operations.makeBookmark(resolved.url), forKey: Key.destination.rawValue)
            } catch {
                Logger.process.warning("Could not refresh the destination bookmark: \(error)")
            }
        }
        return access
    }

    private func acquire(_ url: URL) throws -> CopyScopedAccess {
        guard operations.startAccessing(url) else {
            throw CopyBookmarkFailure.accessDenied
        }
        return CopyScopedAccess(url: url, stopAccessing: operations.stopAccessing)
    }
}
