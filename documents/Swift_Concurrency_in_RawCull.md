# Swift Concurrency in RawCull

---

## 1  Why Concurrency Matters in RawCull

RawCull is a macOS photo-culling application that works with Sony A1 ARW raw files. A single RAW file from the A1 can be 50–80 MB. When you open a folder with hundreds of shots, the app must scan metadata, extract embedded JPEG previews, decode thumbnails, and manage a multi-gigabyte in-memory cache — all while keeping the UI perfectly fluid and responsive at 60 fps. Without concurrency that would be impossible.

RawCull is written in Swift 6, which has strict concurrency checking enabled by default. This means the compiler itself verifies thread safety at compile time. The project makes heavy use of Swift's structured concurrency model: actors, async/await, task groups, and the MainActor.

> **Swift 6:** Strict concurrency checking turns data-race warnings into hard compiler errors. Every type that crosses a concurrency boundary must be `Sendable`, and every mutable shared state must be isolated to an actor.

---

## 2  async / await — The Foundation

`async`/`await` is the cornerstone of Swift's structured concurrency model, introduced in Swift 5.5 (WWDC 2021). An async function can suspend itself — yielding the underlying thread to other work — then resume where it left off when the result is ready. Unlike Grand Central Dispatch callbacks, the code reads top-to-bottom like ordinary synchronous code, which makes it far easier to reason about.

### How it looks

```swift
// A normal synchronous function — blocks the calling thread the entire time
func loadImageBlocking(url: URL) -> NSImage? { ... }

// An async function — suspends while waiting; doesn't block any thread
func loadImageAsync(url: URL) async -> NSImage? {
    // 'await' means: "pause here and let other work run until I'm done"
    let data = await fetchDataFromDisk(url: url)
    return NSImage(data: data)
}

// Calling an async function — you must also be in an async context
func showImage() async {
    let image = await loadImageAsync(url: someURL)  // suspends here
    updateUI(image)                                  // resumes on same actor
}
```

In RawCull, virtually every file-loading, cache-lookup, and thumbnail-generation operation is `async`. This keeps the main thread (and therefore the UI) always free.

---

## 3  Actors — Thread-Safe Isolated State

An actor is a reference type (like a class) that protects its mutable state with automatic mutual exclusion. Only one caller can execute inside an actor at a time. You don't need locks, dispatch queues, or semaphores — the Swift runtime enforces the isolation. If you try to read an actor's property from outside without `await`, the compiler refuses to compile.

**The rule in one sentence:** Every stored property of an actor is only readable and writable from within that actor's own methods. All other callers must `await` a method call to hop onto the actor.

### RawCull's actors at a glance

| Actor | File | Responsibility |
|---|---|---|
| `ScanFiles` | `Actors/ScanFiles.swift` | Scans a folder for ARW files, reads EXIF, extracts focus points |
| `ScanAndCreateThumbnails` | `Actors/ScanAndCreateThumbnails.swift` | Orchestrates bulk thumbnail creation with a concurrent task group |
| `RequestThumbnail` | `Actors/RequestThumbnail.swift` | On-demand thumbnail resolver (RAM → disk → extract) |
| `ThumbnailLoader` | `Actors/ThumbnailLoader.swift` | Rate-limits concurrent thumbnail requests using continuations |
| `DiskCacheManager` | `Actors/DiskCacheManager.swift` | Reads and writes JPEG thumbnails to/from the on-disk cache |
| `SharedMemoryCache` | `Actors/SharedMemoryCache.swift` | Singleton wrapping NSCache; manages memory pressure and config |
| `ExtractAndSaveJPGs` | `Actors/ExtractAndSaveJPGs.swift` | Extracts full-resolution JPEGs from ARW files in parallel |
| `DiscoverFiles` | `Actors/DiscoverFiles.swift` | Recursively enumerates `.arw` files in a directory |
| `ActorCreateOutputforView` | `Actors/ActorCreateOutputforView.swift` | Converts rsync output strings to `RsyncOutputData` structs |

### A minimal actor example from the project

```swift
// From Actors/DiscoverFiles.swift
actor DiscoverFiles {

    // @concurrent tells Swift: run this method on the cooperative thread pool,
    // not on the actor's serial queue. Safe because the method only uses
    // local variables — no actor state is touched.
    @concurrent
    nonisolated func discoverFiles(at catalogURL: URL, recursive: Bool) async -> [URL] {
        await Task {
            let supported: Set<String> = [SupportedFileType.arw.rawValue]
            let fileManager = FileManager.default
            var urls: [URL] = []
            guard let enumerator = fileManager.enumerator(
                at: catalogURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: recursive ? [] : [.skipsSubdirectoryDescendants]
            ) else { return urls }
            while let fileURL = enumerator.nextObject() as? URL {
                if supported.contains(fileURL.pathExtension.lowercased()) {
                    urls.append(fileURL)
                }
            }
            return urls
        }.value
    }
}
```

`discoverFiles` is both `nonisolated` and `@concurrent`. Because it never reads or writes any property of the actor, it does not need to run on the actor's serial queue — Swift can run it on any available thread in the cooperative pool, improving throughput.

---

## 4  @MainActor — Protecting the UI Thread

The main thread in a macOS/iOS app is special: all UI rendering must happen there. Swift's `@MainActor` annotation is a global actor that ensures any code it annotates runs exclusively on the main thread. This replaces the old pattern of `DispatchQueue.main.async { ... }` with something the compiler can verify.

### RawCullViewModel — the whole class lives on @MainActor

```swift
// From Model/ViewModels/RawCullViewModel.swift

@Observable @MainActor         // <-- every property and method is main-thread only
final class RawCullViewModel {

    var files: [FileItem] = []           // Safe: only touched on main thread
    var filteredFiles: [FileItem] = []   // Safe: same
    var creatingthumbnails: Bool = false // Drives UI animations

    func handleSourceChange(url: URL) async {
        // 'async' lets the function suspend while waiting for actor work,
        // but it always starts and ends on the main thread (because of @MainActor)
        scanning = true
        let scan = ScanFiles()           // Create a ScanFiles actor
        files = await scan.scanFiles(url: url)  // Hop to ScanFiles actor, wait, return
        // Back on main thread here — safe to update UI
        scanning = false
    }
}
```

When `handleSourceChange` calls `await scan.scanFiles(...)`, the main thread suspends (it is **not** blocked — it continues to process other UI events). When the scan is done, Swift automatically resumes on the main thread before assigning to `files`. This is the key insight: `@MainActor` + `async`/`await` means you never have to manually dispatch back to the main thread.

### ExecuteCopyFiles — another @MainActor class

```swift
// From Model/ParametersRsync/ExecuteCopyFiles.swift

@Observable @MainActor
final class ExecuteCopyFiles {

    private func handleProcessTermination(
        stringoutputfromrsync: [String]?,
        hiddenID: Int?
    ) async {
        let viewOutput = await ActorCreateOutputforView()
                                .createOutputForView(stringoutputfromrsync)

        let result = CopyDataResult(output: stringoutputfromrsync,
                                    viewOutput: viewOutput,
                                    linesCount: stringoutputfromrsync?.count ?? 0)
        onCompletion?(result)

        // Ensure completion handler finishes before cleaning up resources
        try? await Task.sleep(for: .milliseconds(10))
        cleanup()
    }
}
```

> **Why the sleep?** The brief `Task.sleep` before `cleanup()` is an intentional concurrency fix. Without it, there was a race condition: the security-scoped resource access could be released before the `onCompletion` callback had finished using it.

### Crossing the boundary with MainActor.run

```swift
// From Model/ViewModels/SettingsViewModel.swift

// nonisolated means this is accessible without an actor hop,
// but to safely READ the @Observable properties we still need
// to jump to the MainActor for just a moment.

nonisolated func asyncgetsettings() async -> SavedSettings {
    await MainActor.run {               // Hop to main thread, read, return
        SavedSettings(
            memoryCacheSizeMB: self.memoryCacheSizeMB,
            thumbnailSizeGrid: self.thumbnailSizeGrid,
            thumbnailSizePreview: self.thumbnailSizePreview,
            thumbnailSizeFullSize: self.thumbnailSizeFullSize,
            thumbnailCostPerPixel: self.thumbnailCostPerPixel,
            thumbnailSizeGridView: self.thumbnailSizeGridView,
            useThumbnailAsZoomPreview: self.useThumbnailAsZoomPreview
        )
    }   // Back to the calling actor with a Sendable value type
}
```

This pattern — `nonisolated` async function + `MainActor.run` — is the standard way to safely read `@Observable` (main-thread) properties from background actors. `SavedSettings` is a plain `Codable` struct (a value type), so it is `Sendable` and safe to return across the actor boundary.

---

## 5  Task Groups — Parallel File Processing

When you have a collection of independent items to process — like hundreds of RAW files — you want to process them in parallel, not one by one. Swift's `withTaskGroup` (and its throwing counterpart `withThrowingTaskGroup`) let you spawn many child tasks and collect their results. The group automatically limits the number of tasks that run at once based on the cooperative thread pool.

### Thumbnail preloading with withTaskGroup

```swift
// From Actors/ScanAndCreateThumbnails.swift

func preloadCatalog(at catalogURL: URL, targetSize: Int) async -> Int {
    await ensureReady()
    cancelPreload()   // Cancel any ongoing previous preload

    let task = Task<Int, Never> {
        successCount = 0
        let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
        totalFilesToProcess = urls.count

        return await withTaskGroup(of: Void.self) { group in
            // Allow up to (CPU cores × 2) concurrent thumbnail jobs
            let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

            for (index, url) in urls.enumerated() {
                if Task.isCancelled {
                    group.cancelAll()   // Propagate cancellation to child tasks
                    break
                }

                // Once we've queued maxConcurrent tasks, wait for one to finish
                // before adding more — this is backpressure / throttling
                if index >= maxConcurrent {
                    await group.next()
                }

                group.addTask {
                    await self.processSingleFile(url, targetSize: targetSize, itemIndex: index)
                }
            }

            await group.waitForAll()
            return successCount
        }
    }

    preloadTask = task         // Store so we can cancel it later
    return await task.value
}
```

The `maxConcurrent` throttle is important: if you queued 2,000 tasks at once, Swift would create 2,000 concurrent tasks competing for CPU and disk I/O. Instead, RawCull keeps at most `(active CPU cores × 2)` tasks in flight at any one time. When one finishes (`await group.next()`), the loop adds the next one.

### Parallel focus-point extraction in ScanFiles

```swift
// From Actors/ScanFiles.swift

private func extractNativeFocusPoints(from items: [FileItem]) async -> [DecodeFocusPoints]? {
    let collected = await withTaskGroup(of: DecodeFocusPoints?.self) { group in
        for item in items {
            group.addTask {
                // SonyMakerNoteParser.focusLocation is a pure function — no shared state
                guard let location = SonyMakerNoteParser.focusLocation(from: item.url)
                else { return nil }
                return DecodeFocusPoints(
                    sourceFile: item.url.lastPathComponent,
                    focusLocation: location
                )
            }
        }

        // Collect results as tasks complete (order not guaranteed)
        var results: [DecodeFocusPoints] = []
        for await result in group {
            if let r = result { results.append(r) }
        }
        return results
    }
    return collected.isEmpty ? nil : collected
}
```

---

## 6  Task Cancellation — Cooperative, Not Forceful

Swift concurrency uses cooperative cancellation. You cannot forcefully kill a `Task`; instead, you call `task.cancel()` to set a cancellation flag, and the task's code must periodically check `Task.isCancelled` and stop voluntarily. This is the correct pattern: clean shutdown instead of dangling resources.

### How RawCull cancels thumbnail preloading

```swift
// From Model/ViewModels/RawCullViewModel.swift

func abort() {
    // 1. Cancel the outer Task wrapper
    preloadTask?.cancel()
    preloadTask = nil

    // 2. Tell the actor to cancel its internal Task too
    if let actor = currentScanAndCreateThumbnailsActor {
        Task { await actor.cancelPreload() }
    }
    currentScanAndCreateThumbnailsActor = nil

    // 3. Cancel JPG extraction the same way
    if let actor = currentExtractAndSaveJPGsActor {
        Task { await actor.cancelExtractJPGSTask() }
    }
    currentExtractAndSaveJPGsActor = nil

    creatingthumbnails = false
}
```

### Checking cancellation inside the worker

```swift
// From Actors/ScanAndCreateThumbnails.swift

private func processSingleFile(_ url: URL, targetSize: Int, itemIndex: Int) async {
    // Check before doing any I/O
    if Task.isCancelled { return }

    // Check RAM cache...
    if let wrapper = SharedMemoryCache.shared.object(forKey: url as NSURL) { ... }

    // Check again before slower disk operation
    if Task.isCancelled { return }

    // Load from disk cache...
    if let diskImage = await diskCache.load(for: url) { ... }

    // Check again before the most expensive operation: raw file extraction
    if Task.isCancelled { return }

    let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(...)
}
```

Each `Task.isCancelled` guard cuts work short at logical checkpoints. The more expensive the upcoming operation, the more important the guard is. This gives smooth, instant response when the user switches to a different folder.

---

## 7  Task and Task.detached

Sometimes you want to start background work without awaiting its result — a fire-and-forget pattern. Swift provides two ways to do this:

- **`Task { ... }`** — inherits the current actor context and task priority. If called from `@MainActor`, it also runs on `@MainActor` unless it `await`s something that moves it elsewhere.
- **`Task.detached { ... }`** — starts a completely independent task. It inherits no actor context and runs on the cooperative thread pool at the specified priority. Use this for genuinely background work that has no relationship to the calling context.

### Saving to disk in the background (Task.detached)

```swift
// From Actors/ScanAndCreateThumbnails.swift

// We have a cgImage — encode it to Data INSIDE this actor
// before crossing any boundary. CGImage is NOT Sendable.
guard let jpegData = DiskCacheManager.jpegData(from: cgImage) else { return }
// Data IS Sendable — safe to pass to a detached task.

let dcache = diskCache   // Capture the actor reference (actors are Sendable)
Task.detached(priority: .background) {
    // Runs on a background thread — no actor context
    await dcache.save(jpegData, for: url)
}
// We DON'T await this — the thumbnail is shown immediately
// while the disk write happens silently in the background.
```

This is a key pattern: encode the image to `Data` (a value type, `Sendable`) while still inside the actor that owns the `CGImage`. Only after encoding do we hand it off to a detached task. This avoids the Swift 6 compile error that would occur if we tried to send a `CGImage` across a task boundary.

### UI callback fire-and-forget (Task on @MainActor)

```swift
// From Actors/ScanAndCreateThumbnails.swift

private func notifyFileHandler(_ count: Int) {
    let handler = fileHandlers?.fileHandler
    Task { @MainActor in handler?(count) }
    // Creates a Task that runs on the main thread,
    // but we immediately return without awaiting it.
    // Thumbnail generation must NOT stall waiting for UI rendering.
}
```

---

## 8  SharedMemoryCache — A Singleton Actor

`SharedMemoryCache` is one of the most sophisticated concurrency designs in RawCull. It is a singleton actor that wraps `NSCache` (Apple's automatic memory-evicting cache). It cleverly combines actor isolation for configuration with `nonisolated` access for the `NSCache` itself.

```swift
// From Actors/SharedMemoryCache.swift (simplified)

actor SharedMemoryCache {
    // Singleton — accessible as SharedMemoryCache.shared from any context
    nonisolated static let shared = SharedMemoryCache()

    // ── Actor-isolated state (requires await to access) ──────────────────
    private var _costPerPixel: Int = 4
    private var savedSettings: SavedSettings?
    private var setupTask: Task<Void, Never>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    // ── Non-isolated state (no await needed) ─────────────────────────────
    // NSCache is internally thread-safe, so we can safely bypass the
    // actor's serialization for fast synchronous lookups.
    nonisolated(unsafe) let memoryCache = NSCache<NSURL, DiscardableThumbnail>()

    // Synchronous cache lookup — no 'await' required by callers
    nonisolated func object(forKey key: NSURL) -> DiscardableThumbnail? {
        memoryCache.object(forKey: key)
    }
    nonisolated func setObject(_ obj: DiscardableThumbnail, forKey key: NSURL, cost: Int) {
        memoryCache.setObject(obj, forKey: key, cost: cost)
    }
}
```

The key insight is the two-tier design. Configuration properties (cost per pixel, settings, memory pressure source) are actor-isolated and require `await`. But the hot-path `NSCache` operations (lookups and insertions) are `nonisolated` — they happen in every SwiftUI view that renders a thumbnail, and they must be fast. `NSCache` provides its own thread safety, so `nonisolated(unsafe)` is legitimate here.

### Guarding against duplicate initialization with a stored Task

```swift
func ensureReady(config: CacheConfig? = nil) async {
    // If setup is already in progress (or done), just wait for it to finish
    if let task = setupTask {
        return await task.value   // Join the existing task — don't start a new one
    }

    // Start a new setup task — store it IMMEDIATELY before awaiting
    let newTask = Task {
        self.startMemoryPressureMonitoring()
        let settings = await SettingsViewModel.shared.asyncgetsettings()
        let config   = self.calculateConfig(from: settings)
        self.applyConfig(config)
    }

    // Storing BEFORE awaiting is critical: if another caller arrives during
    // the await below, they'll find setupTask already set and join it.
    setupTask = newTask
    await newTask.value
}
```

> **Race condition fix:** If you stored `setupTask = newTask` *after* `await newTask.value`, a second concurrent caller could find `setupTask` still `nil` and start a duplicate initialization. Storing it immediately after creation is the correct pattern.

### Memory pressure monitoring with DispatchSource

```swift
private func startMemoryPressureMonitoring() {
    let source = DispatchSource.makeMemoryPressureSource(
        eventMask: .all, queue: .global(qos: .utility)
    )

    // When the OS fires a memory pressure event (on a GCD background queue),
    // we create a Task to hop back onto the actor and respond.
    source.setEventHandler { [weak self] in
        guard let self else { return }
        Task {
            await self.handleMemoryPressureEvent()
        }
    }

    source.resume()
    memoryPressureSource = source
}
```

---

## 9  AsyncStream — Streaming Progress Updates

`AsyncStream` is Swift's way to model a sequence of values that arrive over time — analogous to a Combine publisher or a Unix pipe, but using async/await. RawCull uses `AsyncStream` to stream progress updates from the rsync copy process to the UI.

```swift
// From Model/ParametersRsync/ExecuteCopyFiles.swift

// In init(): create an AsyncStream with its continuation
let (stream, continuation) = AsyncStream.makeStream(of: Int.self)
self.progressStream       = stream        // Consumer reads from this
self.progressContinuation = continuation  // Producer writes to this

// ── Producer (inside streaming handler callback) ─────────────────────────
streamingHandlers = CreateStreamingHandlers().createHandlersWithCleanup(
    fileHandler: { [weak self] count in
        // Each time rsync reports a file, yield the count to the stream
        self?.progressContinuation?.yield(count)
    }
)

// ── Consumer (in a ViewModel or View) ────────────────────────────────────
if let stream = copyFiles.progressStream {
    for await count in stream {
        // 'await' suspends between each value — no busy-waiting
        updateProgressBar(count)
    }
    // Loop exits naturally when continuation.finish() is called
}

// ── Cleanup (inside handleProcessTermination) ─────────────────────────────
progressContinuation?.finish()   // Signals the consumer loop to exit
progressContinuation = nil
progressStream = nil
```

`AsyncStream` is ideal here: rsync is a long-running subprocess that emits a count each time it copies a file. The UI wants to see each update as it happens, without polling. When the process finishes, calling `.finish()` on the continuation terminates the `for await` loop cleanly.

---

## 10  CheckedContinuation — Bridging to the Semaphore World

Swift's concurrency model doesn't have a built-in semaphore. Instead, you use `withCheckedContinuation` (or its throwing variant) to suspend a task and resume it later from a completely different context. `ThumbnailLoader` uses this to build a rate-limiter — a queue that allows at most 6 concurrent thumbnail loads at once.

```swift
// From Actors/ThumbnailLoader.swift

actor ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let maxConcurrent = 6
    private var activeTasks  = 0
    private var pendingContinuations: [(id: UUID, continuation: CheckedContinuation<Void, Never>)] = []

    private func acquireSlot() async {
        if activeTasks < maxConcurrent {
            activeTasks += 1
            return   // Slot available — proceed immediately
        }

        // No slot available — suspend this task and wait
        let id = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // We are now suspended. Store the continuation.
                // releaseSlot() will call continuation.resume() when a slot opens.
                pendingContinuations.append((id: id, continuation: continuation))
            }
            activeTasks += 1
        } onCancel: {
            // If the task is cancelled while waiting, remove it from the queue
            Task { await self.removeAndResumePendingContinuation(id: id) }
        }
    }

    private func releaseSlot() {
        activeTasks -= 1
        if let next = pendingContinuations.first {
            pendingContinuations.removeFirst()
            next.continuation.resume()   // Wake up the oldest waiting task
        }
    }

    func thumbnailLoader(file: FileItem) async -> NSImage? {
        await acquireSlot()              // Wait for a free slot
        defer { releaseSlot() }          // Release when done (even on error)

        guard !Task.isCancelled else { return nil }
        // ... load thumbnail ...
    }
}
```

`withCheckedContinuation` is Swift's way to wrap callback-based or semaphore-based APIs into the async/await world. The "Checked" version adds runtime safety: if you forget to call `resume()` exactly once, the program crashes with a clear error rather than silently deadlocking. `withTaskCancellationHandler` ensures that if the task is cancelled while waiting for a slot, it cleans up gracefully.

---

## 11  The Thumbnail Pipeline — Putting It All Together

The thumbnail system is where all the concurrency patterns converge. Understanding this pipeline shows how each concept connects in practice.

### Three-tier lookup strategy (RAM → Disk → Extract)

```swift
// From Actors/ScanAndCreateThumbnails.swift (resolveImage, simplified)

private func resolveImage(for url: URL, targetSize: Int) async throws -> CGImage {

    // ── Tier A: RAM (synchronous — no await needed) ───────────────────────
    // SharedMemoryCache.shared.object() is nonisolated — no actor hop.
    if let wrapper = SharedMemoryCache.shared.object(forKey: url as NSURL),
       wrapper.beginContentAccess() {
        defer { wrapper.endContentAccess() }
        return try nsImageToCGImage(wrapper.image)   // Fastest path: ~μs
    }

    // ── Tier B: Disk cache (async — file I/O) ─────────────────────────────
    if let diskImage = await diskCache.load(for: url) {
        storeInMemoryCache(diskImage, for: url)      // Promote to RAM
        return try nsImageToCGImage(diskImage)        // Fast: ~ms
    }

    // ── Tier C: In-flight deduplication ───────────────────────────────────
    // If another caller is already generating this thumbnail, join that task
    // instead of starting a duplicate.
    if let existingTask = inflightTasks[url] {
        let image = try await existingTask.value
        return try nsImageToCGImage(image)
    }

    // ── Tier D: Extract from raw file ─────────────────────────────────────
    let task = Task { () throws -> NSImage in
        let cgImage = try await SonyThumbnailExtractor.extractSonyThumbnail(
            from: url, maxDimension: CGFloat(targetSize), qualityCost: costPerPixel
        )
        let image = try cgImageToNormalizedNSImage(cgImage)
        storeInMemoryCache(image, for: url)

        // Encode to Data inside this actor, then fire off a background save
        if let jpegData = DiskCacheManager.jpegData(from: cgImage) {
            Task.detached(priority: .background) { await dcache.save(jpegData, for: url) }
        }
        inflightTasks[url] = nil
        return image
    }
    inflightTasks[url] = task     // Register so concurrent callers can join it
    return try nsImageToCGImage(try await task.value)
}
```

Tier C is an elegant optimization called **request coalescing**. If the grid view shows 20 thumbnails and 5 of them are for the same URL (perhaps during a layout transition), only one extraction happens — the other 4 join the first task and share its result.

---

## 12  CacheDelegate — Tracking Evictions with an Actor

`NSCache` can evict objects at any time (when memory gets tight). `CacheDelegate` conforms to `NSCacheDelegate` so it gets a callback when an eviction happens. The tricky part: this callback is called from `NSCache`'s internal C++ thread — not from any Swift actor. The solution is a nested actor that owns the mutable counter.

```swift
// From Model/Cache/CacheDelegate.swift

final class CacheDelegate: NSObject, NSCacheDelegate, @unchecked Sendable {
    nonisolated static let shared = CacheDelegate()

    private let evictionCounter = EvictionCounter()

    // Called by NSCache on its own internal thread
    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>,
                           willEvictObject obj: Any) {
        if obj is DiscardableThumbnail {
            Task {
                let count = await evictionCounter.increment()
                // log the count...
            }
        }
    }

    func getEvictionCount() async -> Int { await evictionCounter.getCount() }
    func resetEvictionCount() async      { await evictionCounter.reset()    }
}

// A private actor that safely owns the mutable counter
private actor EvictionCounter {
    private var count = 0
    func increment() -> Int { count += 1; return count }
    func getCount()  -> Int { count }
    func reset()             { count = 0 }
}
```

`EvictionCounter` is a textbook use of an actor for the simplest possible case: protecting a single integer from concurrent writes. Before actors existed, you would use `NSLock` or `DispatchQueue(label:)` for this. The actor is cleaner, safer, and compiler-verified.

---

## 13  MemoryViewModel — Offloading Heavy Work from @MainActor

`MemoryViewModel` displays live memory statistics (total RAM, used RAM, app footprint). Getting these stats requires Mach kernel calls (`vm_statistics64`, `task_vm_info`) — synchronous system calls that block for a brief moment. If run directly on `@MainActor`, they would cause UI stutter.

```swift
// From Model/ViewModels/MemoryViewModel.swift

func updateMemoryStats() async {
    // Step 1: Move the heavy work OFF the MainActor
    let (total, used, app, threshold) = await Task.detached {
        let total     = ProcessInfo.processInfo.physicalMemory
        let used      = self.getUsedSystemMemory()   // Blocking Mach call
        let app       = self.getAppMemory()           // Blocking Mach call
        let threshold = self.calculateMemoryPressureThreshold(total: total)
        return (total, used, app, threshold)
    }.value

    // Step 2: Update @Observable properties back on MainActor
    await MainActor.run {
        self.totalMemory            = total
        self.usedMemory             = used
        self.appMemory              = app
        self.memoryPressureThreshold = threshold
    }
}

// The Mach calls are nonisolated: they don't touch any actor state
private nonisolated func getUsedSystemMemory() -> UInt64 {
    var stat = vm_statistics64()
    // ... kernel call ...
    return (wired + active + compressed) * pageSize
}
```

This pattern — `Task.detached` for blocking work, then `MainActor.run` to update observable state — is the canonical way to keep the UI thread responsive while doing expensive computation or I/O in a class that must also update the UI.

---

## 14  @concurrent and nonisolated

Two related annotations help you escape actor isolation when it is safe to do so, allowing more work to run in parallel.

### nonisolated — opt out of the actor's serial queue

A `nonisolated` method on an actor can be called without `await` from outside the actor. The tradeoff: it must not read or write any actor-isolated property. It is safe for pure computation or for accessing `nonisolated(unsafe)` properties.

```swift
// From Actors/ScanFiles.swift

// sortFiles does not touch any actor property — it only works on
// the passed-in 'files' array (a value type, passed by copy).
@concurrent
nonisolated func sortFiles(
    _ files: [FileItem],
    by sortOrder: [some SortComparator<FileItem>],
    searchText: String
) async -> [FileItem] {
    let sorted = files.sorted(using: sortOrder)
    return searchText.isEmpty ? sorted
           : sorted.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
}
```

### @concurrent — run on the thread pool, not the actor queue

`@concurrent` is a Swift 6 annotation that says: "even though this method is on an actor, execute it on the cooperative thread pool, not on the actor's serial queue." It is useful for pure CPU work that doesn't need actor isolation but lives on an actor for organizational reasons.

```swift
// From Actors/ActorCreateOutputforView.swift

actor ActorCreateOutputforView {
    // Pure mapping: [String] → [RsyncOutputData]
    @concurrent
    nonisolated func createOutputForView(_ strings: [String]?) async -> [RsyncOutputData] {
        guard let strings else { return [] }
        return strings.map { RsyncOutputData(record: $0) }
    }
}
```

---

## 15  Sendable — The Type-Safety Rule

A `Sendable` type can safely cross actor/task boundaries. Swift enforces this at compile time in Swift 6: if you try to send a non-`Sendable` value to a different isolation domain, the compiler rejects it. The most common pattern in RawCull is the `CGImage`-to-`Data` conversion before any boundary crossing.

```swift
// CGImage is NOT Sendable (it wraps a C++ object)

// ❌ WRONG — Swift 6 compiler error
Task.detached {
    await diskCache.save(cgImage, for: url)  // Error: CGImage is not Sendable
}

// ✅ CORRECT — Encode to Data first, then cross the boundary
// Data is a struct (value type) — it IS Sendable.
if let jpegData = DiskCacheManager.jpegData(from: cgImage) {
    let dcache = diskCache  // Actor references are Sendable
    Task.detached(priority: .background) {
        await dcache.save(jpegData, for: url)  // Data ✓, actor ref ✓
    }
}
```

Value types (structs, enums) with only `Sendable` stored properties are automatically `Sendable`. `SavedSettings`, `FileItem`, `ExifMetadata`, `CopyDataResult` — all structs in RawCull — are `Sendable` for this reason. Actor references are also `Sendable` (the actor itself serializes access). Class instances are generally not `Sendable` unless annotated.

---

## 16  Bridging GCD and Swift Concurrency — Preventing Thread Pool Starvation

Both `JPGSonyARWExtractor` and `SonyThumbnailExtractor` are caseless enums — pure namespaces with no instance state — that perform CPU-intensive ImageIO work. They use a pattern that looks surprising at first: they explicitly dispatch to `DispatchQueue.global` inside a `withCheckedContinuation`. Understanding why reveals an important pitfall of Swift's cooperative thread pool.

### The problem: thread pool starvation

Swift's cooperative thread pool has a limited number of threads — typically one per CPU core. When an `async` function calls a **synchronous, blocking** API (like `CGImageSourceCreateWithURL` or `CGImageSourceCreateThumbnailAtIndex`), that call does not suspend — it **blocks** the thread it is running on. If many tasks do this simultaneously, every thread in the pool can become occupied with blocked I/O, leaving no threads free to run other `await` continuations. The app effectively freezes. This is called **thread pool starvation**.

The fix is to deliberately hop off the cooperative thread pool and onto a GCD global queue — which has its own, much larger pool of threads — for the duration of the blocking call. When the GCD block finishes, it calls `continuation.resume()`, which re-queues the Swift task on the cooperative pool for the lightweight work that follows.

### JPGSonyARWExtractor — withCheckedContinuation + GCD

```swift
// From Enum/JPGSonyARWExtractor.swift

// @preconcurrency suppresses Sendable errors for AppKit types (like NSImage)
// that predate Swift concurrency and are not formally Sendable.
@preconcurrency import AppKit

enum JPGSonyARWExtractor {
    static func jpgSonyARWExtractor(
        from arwURL: URL,
        fullSize: Bool = false,
    ) async -> CGImage? {

        return await withCheckedContinuation { continuation in
            // Dispatch to GCD to prevent Thread Pool Starvation.
            // CGImageSourceCreateWithURL and friends are synchronous and can
            // block for tens of milliseconds on a large ARW file.
            // Running them directly on the cooperative pool ties up a thread.
            DispatchQueue.global(qos: .utility).async {

                guard let imageSource = CGImageSourceCreateWithURL(arwURL as CFURL, nil) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Scan all sub-images in the ARW container and find the largest JPEG preview
                let imageCount = CGImageSourceGetCount(imageSource)
                var targetIndex = -1
                var targetWidth  = 0

                for index in 0 ..< imageCount {
                    guard let props = CGImageSourceCopyPropertiesAtIndex(imageSource, index, nil)
                            as? [CFString: Any] else { continue }

                    let hasJFIF     = (props[kCGImagePropertyJFIFDictionary] as? [CFString: Any]) != nil
                    let tiffDict    = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
                    let compression = tiffDict?[kCGImagePropertyTIFFCompression] as? Int
                    let isJPEG      = hasJFIF || (compression == 6)  // TIFF compression 6 = JPEG

                    if let width = getWidth(from: props), isJPEG, width > targetWidth {
                        targetWidth = width
                        targetIndex = index
                    }
                }

                guard targetIndex != -1 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Downsample in-place with ImageIO if the preview is larger than needed
                let maxSize = CGFloat(fullSize ? 8640 : 4320)
                let result: CGImage?

                if CGFloat(targetWidth) > maxSize {
                    let options: [CFString: Any] = [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform:   true,
                        kCGImageSourceThumbnailMaxPixelSize:           Int(maxSize),
                    ]
                    result = CGImageSourceCreateThumbnailAtIndex(imageSource, targetIndex,
                                                                 options as CFDictionary)
                } else {
                    let options: [CFString: Any] = [
                        kCGImageSourceShouldCache:            true,
                        kCGImageSourceShouldCacheImmediately: true,
                    ]
                    result = CGImageSourceCreateImageAtIndex(imageSource, targetIndex,
                                                            options as CFDictionary)
                }

                // Hand the result back to the Swift async world
                continuation.resume(returning: result)
            }
        }
    }
}
```

The `withCheckedContinuation` call suspends the Swift task and stores its continuation. The GCD block then runs on a GCD worker thread — entirely outside the cooperative pool. When it calls `continuation.resume(returning:)`, Swift schedules the task to resume, but only the lightweight resumption, not the expensive ImageIO work that has already completed on GCD.

### SonyThumbnailExtractor — withCheckedThrowingContinuation + GCD

`SonyThumbnailExtractor` follows the same pattern but uses the **throwing** variant because the ImageIO operations can fail. The comment in the source file spells out a second important motivation beyond starvation:

```swift
// From Enum/SonyThumbnailExtractor.swift

enum SonyThumbnailExtractor {
    static func extractSonyThumbnail(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int = 4,
    ) async throws -> CGImage {

        // We MUST explicitly hop off the current thread.
        // Since we are an enum and static, we have no isolation of our own.
        // If we don't do this, we run on the caller's thread (the Actor),
        // causing serialization — only one extraction at a time.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let image = try Self.extractSync(from: url,
                                                    maxDimension: maxDimension,
                                                    qualityCost: qualityCost)
                    continuation.resume(returning: image)
                } catch {
                    continuation.resume(throwing: error)  // Propagates to the call site
                }
            }
        }
    }

    // All heavy ImageIO work lives in a private synchronous function,
    // only ever called from the GCD block above
    private nonisolated static func extractSync(
        from url: URL,
        maxDimension: CGFloat,
        qualityCost: Int,
    ) throws -> CGImage {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions)
        else { throw ThumbnailError.invalidSource }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform:   true,
            kCGImageSourceThumbnailMaxPixelSize:           maxDimension,
            kCGImageSourceShouldCacheImmediately:          true,
        ]
        guard let raw = CGImageSourceCreateThumbnailAtIndex(source, 0,
                                                            thumbOptions as CFDictionary)
        else { throw ThumbnailError.generationFailed }

        return try rerender(raw, qualityCost: qualityCost)
    }

    // Re-renders into an sRGB CGContext to normalise colour space and apply
    // the chosen interpolation quality
    private nonisolated static func rerender(_ image: CGImage, qualityCost: Int) throws -> CGImage {
        let quality: CGInterpolationQuality = switch qualityCost {
            case 1...2: .low
            case 3...4: .medium
            default:    .high
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw ThumbnailError.contextCreationFailed }

        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        else { throw ThumbnailError.contextCreationFailed }

        ctx.interpolationQuality = quality
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = ctx.makeImage() else { throw ThumbnailError.generationFailed }
        return result
    }
}
```

The comment makes an important second point: *"If we don't do this, we run on the caller's thread (the Actor), causing serialization."* Even without starvation, running the blocking work directly on the calling actor would mean the actor can only process **one extraction at a time** — because actors are serial. By dispatching to GCD immediately, the actor is freed to start the next request while GCD runs many extractions concurrently on its own thread pool.

### Why enums, not classes or actors?

Using a caseless `enum` signals that the type is a pure namespace — it has no instance state and cannot be instantiated. This means there is no actor isolation to reason about, every method is inherently `static`, and `self` does not exist. The Swift compiler never has to consider whether the type crosses an isolation boundary. It is the right choice for stateless utility code that performs only I/O and pure computation.

### @preconcurrency import — suppressing legacy Sendable warnings

`JPGSonyARWExtractor` annotates its AppKit import with `@preconcurrency`:

```swift
@preconcurrency import AppKit
```

`AppKit` was written before Swift concurrency existed, so many of its types are not formally declared `Sendable`. In Swift 6, using them across concurrency boundaries would normally produce hard errors. `@preconcurrency import` tells the compiler to treat missing `Sendable` conformances from that module as warnings rather than errors — the sanctioned way to integrate legacy frameworks without turning off strict concurrency checking globally.

### QoS choices — utility vs userInitiated

The two enums deliberately pick different GCD quality-of-service levels:

- `JPGSonyARWExtractor` uses `.utility` — extracting full-resolution previews for JPG export is a background batch job that can yield to foreground work without affecting perceived responsiveness.
- `SonyThumbnailExtractor` uses `.userInitiated` — thumbnail extraction is driven directly by the user scrolling the grid, so results need to appear quickly to keep the UI feeling snappy.

This mirrors the task priority system used within Swift concurrency itself (`Task(priority: .background)` vs `.userInitiated`), applied at the GCD layer where the blocking work actually lives.

---

## 17  Quick Reference

| Keyword / Pattern | What it does | Where in RawCull |
|---|---|---|
| `async` / `await` | Suspend without blocking; resume when ready | Everywhere — all I/O functions |
| `actor` | Reference type with automatic mutual exclusion | `ScanFiles`, `DiskCacheManager`, `ThumbnailLoader`, … |
| `@MainActor` | Restrict execution to the main thread | `RawCullViewModel`, `ExecuteCopyFiles` |
| `@Observable + @MainActor` | SwiftUI-observable classes on main thread | `RawCullViewModel`, `SettingsViewModel` |
| `withTaskGroup` | Fan out many tasks in parallel, collect results | `ScanFiles.scanFiles`, `ScanAndCreateThumbnails.preloadCatalog` |
| `Task { }` | Fire-and-forget; inherits current actor | UI callbacks, rating updates, `abort()` |
| `Task.detached { }` | Fully independent background task | Disk-cache saves, `MemoryViewModel` stats |
| `Task.isCancelled` | Cooperative cancellation check | `processSingleFile` — multiple guard points |
| `task.cancel()` | Request cooperative cancellation | `RawCullViewModel.abort()` |
| `AsyncStream` | Push-based sequence of values over time | `ExecuteCopyFiles` progress stream |
| `CheckedContinuation` (rate-limiter) | Suspend a task; resume it from another context | `ThumbnailLoader.acquireSlot()` |
| `withCheckedContinuation` + `DispatchQueue.global` | Escape the cooperative pool; prevent thread pool starvation | `JPGSonyARWExtractor`, `SonyThumbnailExtractor` |
| `withCheckedThrowingContinuation` | Throwing variant of continuation bridging | `SonyThumbnailExtractor.extractSonyThumbnail` |
| `@preconcurrency import` | Suppress Sendable errors for pre-concurrency frameworks | `JPGSonyARWExtractor` (AppKit) |
| `nonisolated` | Escape actor isolation for pure functions | `ScanFiles.sortFiles`, `SettingsViewModel.asyncgetsettings` |
| `@concurrent` | Run on thread pool, not actor queue | `ScanFiles.sortFiles`, `ActorCreateOutputforView` |
| `nonisolated(unsafe)` | Bypass isolation for externally thread-safe objects | `SharedMemoryCache.memoryCache` (NSCache) |
| `MainActor.run { }` | Hop to main thread for a block, then return | `SettingsViewModel.asyncgetsettings`, `MemoryViewModel.updateMemoryStats` |
| `Sendable` | Types safe to cross actor/task boundaries | `SavedSettings`, `FileItem`, `Data` (CGImage → Data encoding) |

---

*RawCull — a macOS app by Thomas Evensen · Swift 6 strict concurrency · Apple Silicon · macOS 26 Tahoe*
