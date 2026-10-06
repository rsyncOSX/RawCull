import AppKit
import Foundation

/// Synchronizes each cache mutation with its count/cost accounting. NSCache can
/// invoke eviction callbacks during insertion or limit changes, so the lock is
/// recursive: callbacks participate in the same transaction on the calling thread.
/// No lock is held across an await. All mutable state is private and lock-protected;
/// the unchecked conformance is required by the Objective-C delegate boundary.
final nonisolated class TrackedThumbnailCache: NSObject, NSCacheDelegate, @unchecked Sendable {
    private final class Entry: NSObject, Sendable {
        let id = UUID()
        let key: String
        let thumbnail: CachedThumbnail
        let cost: Int

        init(key: String, thumbnail: CachedThumbnail, cost: Int) {
            self.key = key
            self.thumbnail = thumbnail
            self.cost = cost
        }
    }

    private let lock = NSRecursiveLock()
    private let storage = NSCache<NSString, Entry>()
    // Metadata holds no thumbnail references, preserving NSCache eviction.
    private var entries: [String: (id: UUID, cost: Int)] = [:]
    private var storedCost = 0

    override init() {
        super.init()
        storage.delegate = self
    }

    deinit {
        // NSCache teardown can evict entries after our metadata/lock have been
        // destroyed. Detach its non-owning delegate before stored-property teardown.
        storage.delegate = nil
    }

    var totalCostLimit: Int {
        get { locked { storage.totalCostLimit } }
        set { locked { storage.totalCostLimit = newValue } }
    }

    var countLimit: Int {
        get { locked { storage.countLimit } }
        set { locked { storage.countLimit = newValue } }
    }

    var currentCost: Int {
        locked { storedCost }
    }

    var currentCount: Int {
        locked { entries.count }
    }

    func object(forKey key: NSString) -> CachedThumbnail? {
        locked { storage.object(forKey: key)?.thumbnail }
    }

    func setObject(_ thumbnail: CachedThumbnail, forKey key: NSString, cost: Int) {
        locked {
            let entry = Entry(key: key as String, thumbnail: thumbnail, cost: max(0, cost))
            if let previous = entries[entry.key] {
                storedCost -= previous.cost
            }
            // Register first: an immediate eviction during insertion must find
            // this entry, while a replacement callback must ignore the old ID.
            entries[entry.key] = (entry.id, entry.cost)
            storedCost += entry.cost
            storage.setObject(entry, forKey: key, cost: entry.cost)
        }
    }

    func removeAllObjects() {
        locked {
            entries.removeAll()
            storedCost = 0
            storage.removeAllObjects()
        }
    }

    func cache(_: NSCache<AnyObject, AnyObject>, willEvictObject object: Any) {
        guard let entry = object as? Entry else { return }
        locked {
            guard entries[entry.key]?.id == entry.id else { return }
            entries.removeValue(forKey: entry.key)
            storedCost -= entry.cost
        }
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
