import Foundation
import RawCullCore

/// Owns the non-presentation lifetime of the active catalog. Application state
/// changes stay in the view model; this boundary admits transitions only after
/// persistence succeeds and keeps worker access alive independently of selection.
@MainActor
final class CatalogLifecycleCoordinator {
    var currentSource: ARWSourceCatalog?
    private(set) var transitionTask: Task<Void, Never>?
    private(set) var loadTask: Task<Void, Never>?
    var activeLoadURL: URL?

    private var transitionGeneration: UInt64 = 0
    private var activeSecurityScopedGrant: RawCullCatalogGrant?

    var startSecurityScopedResource: @MainActor (URL) -> Bool = {
        $0.startAccessingSecurityScopedResource()
    }

    var stopSecurityScopedResource: @MainActor (URL) -> Void = {
        $0.stopAccessingSecurityScopedResource()
    }

    func startTransition(
        flushPersistence: @escaping @MainActor () async -> Bool,
        isStillSelected: @escaping @MainActor () -> Bool,
        onFailure: @escaping @MainActor () -> Void,
        onReady: @escaping @MainActor () -> Void,
    ) {
        cancelTransition()
        let generation = transitionGeneration
        transitionTask = Task { [weak self] in
            let didFlush = await flushPersistence()
            guard let self else { return }
            defer {
                if transitionGeneration == generation {
                    transitionTask = nil
                }
            }
            guard !Task.isCancelled, transitionGeneration == generation,
                  isStillSelected() else { return }
            if didFlush {
                onReady()
            } else {
                onFailure()
            }
        }
    }

    func cancelTransition() {
        transitionGeneration &+= 1
        transitionTask?.cancel()
        transitionTask = nil
    }

    func startLoad(for url: URL, operation: @escaping @MainActor () async -> Void) {
        activeLoadURL = url
        let access = RawCullCatalogAccess.shared.retainAccess(for: [url])
        loadTask = Task(priority: .background) {
            defer { withExtendedLifetime(access) {} }
            await operation()
        }
    }

    func finishLoad(for url: URL) {
        guard activeLoadURL == url else { return }
        loadTask = nil
        activeLoadURL = nil
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        activeLoadURL = nil
        currentSource = nil
        stopActiveSecurityScopedAccess()
    }

    @discardableResult
    func startSecurityScopedAccess(for url: URL) -> Bool {
        let url = url.standardizedFileURL
        if hasActiveSecurityScopedAccess(for: url) {
            return true
        }
        stopActiveSecurityScopedAccess()
        guard startSecurityScopedResource(url) else { return false }
        let grant = RawCullCatalogGrant(url: url, stopAccess: stopSecurityScopedResource)
        activeSecurityScopedGrant = grant
        RawCullCatalogAccess.shared.register(grant)
        return true
    }

    func hasActiveSecurityScopedAccess(for url: URL) -> Bool {
        activeSecurityScopedGrant?.url == url.standardizedFileURL
    }

    func stopActiveSecurityScopedAccess() {
        activeSecurityScopedGrant = nil
    }

    isolated deinit {
        transitionTask?.cancel()
        loadTask?.cancel()
        activeSecurityScopedGrant = nil
    }
}
