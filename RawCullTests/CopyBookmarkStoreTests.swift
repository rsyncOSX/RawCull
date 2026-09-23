import Foundation
@testable import RawCull
import Testing

@MainActor
struct CopyBookmarkStoreTests {
    @Test
    func `missing and corrupt destination bookmarks fail without acquiring access`() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        var accessCount = 0
        var operations = CopyBookmarkOperations.live
        operations.startAccessing = { _ in
            accessCount += 1
            return true
        }
        let store = CopyBookmarkStore(defaults: defaults, operations: operations)

        #expect(throws: CopyBookmarkFailure.missingDestination) {
            try store.acquireDestination()
        }
        defaults.set(Data("not a bookmark".utf8), forKey: "destBookmark")
        #expect(throws: CopyBookmarkFailure.invalidDestination) {
            try store.acquireDestination()
        }
        #expect(accessCount == 0)
    }

    @Test
    func `failed replacement preserves the saved destination`() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let previous = Data("previous destination".utf8)
        defaults.set(previous, forKey: "destBookmark")
        let url = URL(fileURLWithPath: "/destination")
        var operations = CopyBookmarkOperations.live
        operations.startAccessing = { _ in false }
        let deniedStore = CopyBookmarkStore(defaults: defaults, operations: operations)

        #expect(throws: CopyBookmarkFailure.accessDenied) {
            try deniedStore.saveDestination(url)
        }
        #expect(defaults.data(forKey: "destBookmark") == previous)

        var stopCount = 0
        operations.startAccessing = { _ in true }
        operations.stopAccessing = { _ in stopCount += 1 }
        operations.makeBookmark = { _ in throw CopyBookmarkFailure.couldNotSave }
        let failingStore = CopyBookmarkStore(defaults: defaults, operations: operations)
        #expect(throws: CopyBookmarkFailure.couldNotSave) {
            try failingStore.saveDestination(url)
        }
        #expect(stopCount == 1)
        #expect(defaults.data(forKey: "destBookmark") == previous)
    }

    @Test
    func `saving a destination replaces its bookmark and releases access`() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let destination = URL(fileURLWithPath: "/destination")
        var isAccessing = false
        var stopCount = 0
        var operations = CopyBookmarkOperations.live
        operations.startAccessing = { _ in
            isAccessing = true
            return true
        }
        operations.makeBookmark = { url in
            #expect(url == destination)
            #expect(isAccessing)
            return Data("new destination".utf8)
        }
        operations.stopAccessing = { _ in
            isAccessing = false
            stopCount += 1
        }
        let store = CopyBookmarkStore(defaults: defaults, operations: operations)

        try store.saveDestination(destination)

        #expect(defaults.data(forKey: "destBookmark") == Data("new destination".utf8))
        #expect(!isAccessing)
        #expect(stopCount == 1)
    }

    @Test
    func `stale bookmark refreshes under access and releases once`() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("stale".utf8), forKey: "destBookmark")
        let destination = URL(fileURLWithPath: "/destination")
        var isAccessing = false
        var stopCount = 0
        let operations = CopyBookmarkOperations(
            makeBookmark: { url in
                #expect(url == destination)
                #expect(isAccessing)
                return Data("refreshed".utf8)
            },
            resolveBookmark: { data in
                #expect(data == Data("stale".utf8))
                return (destination, true)
            },
            startAccessing: { url in
                #expect(url == destination)
                isAccessing = true
                return true
            },
            stopAccessing: { url in
                #expect(url == destination)
                isAccessing = false
                stopCount += 1
            },
        )
        let store = CopyBookmarkStore(defaults: defaults, operations: operations)

        let access = try store.acquireDestination()
        #expect(access.url == destination)
        #expect(defaults.data(forKey: "destBookmark") == Data("refreshed".utf8))
        access.release()
        access.release()
        #expect(!isAccessing)
        #expect(stopCount == 1)
    }

    @Test
    func `destination access denial does not change its bookmark`() throws {
        let (defaults, suite) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmark = Data("saved".utf8)
        defaults.set(bookmark, forKey: "destBookmark")
        var operations = CopyBookmarkOperations.live
        operations.resolveBookmark = { _ in (URL(fileURLWithPath: "/destination"), false) }
        operations.startAccessing = { _ in false }
        let store = CopyBookmarkStore(defaults: defaults, operations: operations)

        #expect(throws: CopyBookmarkFailure.accessDenied) {
            try store.acquireDestination()
        }
        #expect(defaults.data(forKey: "destBookmark") == bookmark)
    }

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suite = "RawCullCopyBookmarkStore-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }
}
