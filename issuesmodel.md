# RawCull — Model Layer Issues

Covers: `Actors/`, `Enum/`, `Extensions/`, `Model/`

---

### H1 — `nonisolated(unsafe) currentPressureLevel` data race
**File:** `Actors/SharedMemoryCache.swift`

**Problem:**
`currentPressureLevel` is declared `nonisolated(unsafe)` and written inside the actor via a `Task` spawned from a GCD `DispatchSource` event handler. It is read synchronously from `MemoryViewModel` on the `@MainActor` without any synchronisation. The `nonisolated(unsafe)` opts out of all Swift concurrency checking — this is a genuine data race.

**Fix:** Replace `nonisolated(unsafe)` with an `OSAllocatedUnfairLock` (the same pattern already used in `DiscardableThumbnail`):
```swift
private let _currentPressureLevel = OSAllocatedUnfairLock<MemoryPressureLevel>(initialState: .normal)

var currentPressureLevel: MemoryPressureLevel {
    get { _currentPressureLevel.withLock { $0 } }
    set { _currentPressureLevel.withLock { $0 = newValue } }
}
```

---

## Medium Severity

### M1 — Blocking ImageIO work on `@MainActor`
**File:** `Model/ViewModels/DeepDiveTagsViewModel.swift`

**Problem:**
`load(url:)` is `@MainActor` (inherited from the class) and calls `CGImageSourceCreateWithURL`, `CGImageSourceCopyPropertiesAtIndex`, and `CGImageMetadataEnumerateTagsUsingBlock` synchronously on the main thread. For large ARW files this blocks the UI. There is also no cancellation check inside the metadata enumeration loop.

**Fix:** Move the heavy work off the main actor and publish results back on it:
```swift
func load(url: URL) async {
    let result = await Task.detached(priority: .userInitiated) {
        // All CGImageSource / CGImageMetadata work here — off main thread
        guard !Task.isCancelled else { return [MetadataValue]() }
        ...
        return metadataValues
    }.value
    // Back on MainActor (class is @MainActor)
    self.metadata = result
}
```

---

### M2 — Blocking `Data(contentsOf:)` on `@MainActor` at app startup
**File:** `Model/ViewModels/SettingsViewModel.swift`

**Problem:**
```swift
private init() {
    Task { await loadSettings() }  // inherits MainActor context
}
```
The `Task` inherits the main-actor context from the `@MainActor` `shared` singleton initialiser. `loadSettings()` calls `Data(contentsOf: fileURL)` — synchronous file I/O — on the main thread at app launch.

**Fix:** Detach the I/O work from the main actor:
```swift
private init() {
    Task.detached(priority: .utility) {
        let settings = await Self.readSettingsFromDisk()
        await MainActor.run { self.apply(settings) }
    }
}
```
Or mark the class `@MainActor` and make `loadSettings` `async` with an internal `Task.detached` for the I/O portion.

---

### M3 — `ThumbnailLoader.acquireSlot` — continuation fragility on cancellation
**File:** `Actors/ThumbnailLoader.swift`

**Problem:**
```swift
await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
        pendingContinuations.append((id: id, continuation: continuation))
    }
    activeTasks += 1
} onCancel: {
    Task { await self.removeAndResumePendingContinuation(id: id) }
}
```
`withCheckedContinuation` requires exactly one resume. The cancellation `Task` and the `releaseSlot` path can both attempt to resume the continuation. Safety relies implicitly on actor serialisation — there is no explicit guard against double-resume. Additionally, if `cancelAll()` is called the interaction between `activeTasks` counter increments and the cancellation path is non-obvious.

**Fix:** Use `withTaskCancellationHandler` wrapping an `AsyncStream` or add an explicit `resumed` flag:
```swift
await withTaskCancellationHandler {
    await withCheckedContinuation { continuation in
        pendingContinuations.append((id: id, continuation: continuation, resumed: false))
    }
    activeTasks += 1
} onCancel: {
    Task { await self.cancelPendingContinuation(id: id) }
}

// In cancelPendingContinuation — guard against double resume:
if let index = pendingContinuations.firstIndex(where: { $0.id == id }),
   !pendingContinuations[index].resumed {
    pendingContinuations[index].resumed = true
    pendingContinuations.remove(at: index).continuation.resume()
}
```

---

### M4 — Fire-and-forget `Task {}` in `@MainActor` methods — no cancellation
**Files:** `Model/ViewModels/CullingModel.swift`, `Model/ViewModels/RawCullViewModel.swift`

**Problem:**
```swift
func resetSavedFiles(in catalog: URL) {
    Task { await WriteSavedFilesJSON(savedFiles) }
}
```
The caller has no way to know when the save completes. If the view is dismissed before the task finishes there is no cancellation. Same pattern in `RawCullViewModel.updateRating(for:rating:)` and `RawCullViewModel.abort()`.

**Fix:** Make the methods `async` and `await` the work directly:
```swift
func resetSavedFiles(in catalog: URL) async {
    await WriteSavedFilesJSON(savedFiles)
}
```
If a non-`async` call site requires a fire-and-forget, store the `Task` and cancel it in `deinit` or on view disappear.

---

### M5 — `SavedFiles` `Equatable` ignores `id` and `filerecords` — breaks SwiftUI diffing
**File:** `Model/JSON/SavedFiles.swift`

**Problem:**
`SavedFiles` conforms to both `Identifiable` (uses `id`) and `Equatable` (uses only `dateStart` and `catalog`, ignoring `filerecords`). SwiftUI uses `Identifiable.id` for list identity but may use `Equatable` for change detection. Two `SavedFiles` with different `filerecords` (but same `dateStart` + `catalog`) compare as equal, so SwiftUI won't redraw when records change.

**Fix:** Either include all relevant fields in `==`, or remove the manual `Equatable` conformance and let the compiler synthesise it:
```swift
// Remove the manual == implementation and let Swift synthesise:
// extension SavedFiles: Equatable {}  // synthesised includes all stored properties
```
If a custom `==` is truly needed for sorting/deduplication, document clearly that it is not used for SwiftUI change detection.

---

### M6 — `ZoomPreviewHandler` — closures lack `@MainActor` enforcement
**File:** `Model/Handlers/ZoomPreviewHandler.swift`

**Problem:**
`ZoomPreviewHandler.handle(...)` is a `nonisolated static func` on an enum. It spawns bare `Task {}`s and accepts `@escaping` closures (`setNSImage`, `setCGImage`, `openWindow`) with no `@MainActor` or `@Sendable` annotation. Callers that pass SwiftUI state mutations get no compiler enforcement that those mutations happen on the main thread.

**Fix:** Annotate the closure parameters:
```swift
static func handle(
    url: URL,
    setNSImage: @escaping @MainActor @Sendable (NSImage?) -> Void,
    setCGImage: @escaping @MainActor @Sendable (CGImage?) -> Void,
    openWindow: @escaping @MainActor @Sendable () -> Void
)
```

---

### M7 — `FocusMaskModel` — `@unchecked Sendable` on mutable `@Observable` class
**File:** `Model/ViewModels/FocusMaskModel.swift`

**Problem:**
```swift
@Observable
final class FocusMaskModel: @unchecked Sendable {
```
`FocusMaskModel` is not `@MainActor` but holds mutable `var config`. `@unchecked Sendable` suppresses the Swift concurrency checker without providing thread safety. The `config` property can be mutated from any thread concurrently.

**Fix:** Add `@MainActor` to the class instead of `@unchecked Sendable`:
```swift
@Observable
@MainActor
final class FocusMaskModel { ... }
```

---

### M8 — `ExtractAndSaveJPGs` — all task errors silently swallowed
**File:** `Actors/ExtractAndSaveJPGs.swift`

**Problem:**
```swift
try? await group.next()
try? await group.waitForAll()
```
Inside a `withThrowingTaskGroup`, all errors from child tasks are silently discarded. Failed extractions are invisible to the caller and to logging.

**Fix:** Handle or log errors explicitly:
```swift
do {
    try await group.waitForAll()
} catch {
    Logger.process.error("ExtractAndSaveJPGs failed: \(error)")
}
```

---

### M9 — `MemoryViewModel` — `@Observable` without `@MainActor`
**File:** `Model/ViewModels/MemoryViewModel.swift`

**Problem:**
`MemoryViewModel` is `@Observable` but not `@MainActor`. Property writes are inconsistently protected — some use `MainActor.run { }` while others do not. Concurrent reads from a non-main-actor context can race with writes.

**Fix:** Add `@MainActor` to the class:
```swift
@Observable
@MainActor
final class MemoryViewModel { ... }
```
This makes all property access main-actor-isolated, eliminates the need for `MainActor.run { }` wrappers, and aligns with all other view models in the project.

---

### M10 — `WriteSavedFilesJSON` — `async init` pattern with no-op `@discardableResult`
**File:** `Model/JSON/WriteSavedFilesJSON.swift`

**Problem:**
```swift
@discardableResult
init(_ savedfiles: [SavedFiles]?) async { ... }
```
- `@discardableResult` has no effect on `init` — the compiler ignores it silently.
- Every call site immediately discards the object: `await WriteSavedFilesJSON(savedFiles)`. A new actor is constructed and destroyed for every save, incurring unnecessary overhead.
- An `async init` is unintuitive and makes unit testing awkward (no handle on the object after initialisation).

**Fix:** Replace with a static factory method or a standalone `async` function:
```swift
actor JSONWriter {
    static func write(_ savedFiles: [SavedFiles]?) async {
        // write logic
    }
}
// Call site:
await JSONWriter.write(savedFiles)
```

---

### M11 — Hardcoded dead code — `false ? .ver3 : .openrsync`
**File:** `Model/ParametersRsync/RemoteDataNumbers.swift`

**Problem:**
```swift
let parsersyncoutput = ParseRsyncOutput(preparedoutputfromrsync, false ? .ver3 : .openrsync)
```
The condition is a literal `false`. The `.ver3` branch is unreachable dead code. This suggests an unfinished feature or a forgotten debug toggle.

**Fix:** Either wire the condition to a real runtime value (e.g. from `SettingsViewModel`) or remove the dead branch:
```swift
let parsersyncoutput = ParseRsyncOutput(preparedoutputfromrsync, .openrsync)
```

---

### M12 — Artificial `Task.sleep` before cleanup
**File:** `Model/ParametersRsync/ExecuteCopyFiles.swift`

**Problem:**
```swift
// Give a tiny delay to ensure completion handler processes
try? await Task.sleep(for: .milliseconds(10))
cleanup()
```
A 10 ms sleep is a fragile timing hack. On slow devices the delay may be insufficient; on fast devices it wastes time. Teardown should not be timer-driven.

**Fix:** Make `onCompletion` `async` so cleanup can wait for it to finish:
```swift
await onCompletion?(result)
cleanup()
```
Or use a `CheckedContinuation` / `AsyncStream` to signal when the completion handler is done before calling `cleanup()`.

---

## Low Severity

### L1 — `@concurrent` is not a standard Swift attribute
**Files:** `Actors/ActorCreateOutputforView.swift`, `Actors/DiscoverFiles.swift`, `Actors/ScanFiles.swift`, `Actors/SaveJPGImage.swift`

**Problem:**
`@concurrent` is not a documented Swift attribute in Swift 5.10/6.0 (outside `distributed` contexts). It has no effect and misleads readers into thinking it confers special scheduling behaviour. `nonisolated` alone achieves the intent.

**Fix:** Remove `@concurrent`; keep `nonisolated`:
```swift
nonisolated func discoverFiles(...) async -> [URL] { ... }
```

---

### L2 — Redundant `Task { }.value` inside an `async nonisolated` function
**File:** `Actors/DiscoverFiles.swift`

**Problem:**
```swift
nonisolated func discoverFiles(...) async -> [URL] {
    await Task {
        // synchronous FileManager.enumerator work
    }.value
}
```
The function is already `async` and `nonisolated`, running on a cooperative-pool thread. Wrapping synchronous work in an extra `Task { }.value` provides no threading benefit and adds unnecessary task-creation overhead.

**Fix:** Execute the body directly:
```swift
nonisolated func discoverFiles(...) async -> [URL] {
    var urls: [URL] = []
    // FileManager.enumerator work directly here
    return urls
}
```

---

### L3 — `memorypressurewarning` property and method share the same name
**File:** `Model/ViewModels/RawCullViewModel.swift`

**Problem:**
```swift
var memorypressurewarning: Bool = false

func memorypressurewarning(_ warning: Bool) {
    memorypressurewarning = warning
}
```
A stored property and a method share the exact same identifier. Swift resolves the ambiguity, but the code is confusing and fragile under refactoring.

**Fix:** Rename for clarity:
```swift
var isMemoryPressureWarning: Bool = false

func handleMemoryPressureWarning(_ warning: Bool) {
    isMemoryPressureWarning = warning
}
```

---

### L4 — `SettingsViewModel` — unnecessary `MainActor.run` wrappers
**File:** `Model/ViewModels/SettingsViewModel.swift`

**Problem:**
The class is not annotated `@MainActor`, yet all property mutations wrap themselves in `MainActor.run { }`. This is verbose and inconsistent — it is easy to miss a mutation and introduce a race.

**Fix:** Annotate the class `@MainActor` (consistent with all other view models in the project). All `MainActor.run { }` wrappers can then be removed:
```swift
@Observable
@MainActor
final class SettingsViewModel { ... }
```

---

### L5 — `nonisolated` on `struct` members is a no-op
**Files:** `Model/Cache/CacheConfig.swift`, `Model/Cache/CacheStatistics.swift`

**Problem:**
```swift
struct CacheConfig {
    nonisolated let totalCostLimit: Int
    nonisolated let countLimit: Int
    ...
}
```
`nonisolated` on stored properties of a plain `struct` has no effect — struct values are never actor-isolated. The modifier is misleading.

**Fix:** Remove the `nonisolated` annotations:
```swift
struct CacheConfig {
    let totalCostLimit: Int
    let countLimit: Int
}
```

---

### L6 — Spurious `await` on synchronous logger call
**File:** `Model/JSON/WriteSavedFilesJSON.swift`

**Problem:**
```swift
await Logger.process.errorMessageOnly(...)
```
`Logger.errorMessageOnly` is not `async`. The `await` generates a compiler warning and misleads readers into thinking the call suspends.

**Fix:** Remove the `await`:
```swift
Logger.process.errorMessageOnly(...)
```

---

### L7 — `ReadSavedFilesJSON` — thin `@MainActor` class wrapping a single call
**File:** `Model/JSON/ReadSavedFilesJSON.swift`

**Problem:**
`ReadSavedFilesJSON` is a `@MainActor final class` whose only purpose is to call one method. Every call site creates and immediately discards the object: `ReadSavedFilesJSON().readjsonfilesavedfiles()`. The class adds allocation overhead, a `deinit` log line, and unnecessary `@MainActor` class overhead.

**Fix:** Convert to a `static func` or free function:
```swift
enum SavedFilesReader {
    @MainActor
    static func read() -> [SavedFiles] {
        DecodeSavedFiles().decodeArray(...)
    }
}
```

---

### L8 — Redundant `.extensions` computed property on `SupportedFileType`
**File:** `Extensions/SupportedFileType.swift`

**Problem:**
The `.extensions` computed property returns single-element arrays that duplicate what `.rawValue` already provides. No call site needs the array form.

**Fix:** Remove the `extensions` property and use `.rawValue` directly at call sites.

---

### L9 — Calendar date utilities appear unused in this app
**File:** `Extensions/extension+String+Date.swift`

**Problem:**
The file contains `Date` extension methods for calendar grids (`calendarDisplayDays`, `capitalizedFirstLettersOfWeekdays`, `fullMonthNames`, `firstWeekDayBeforeStart`, etc.). These appear to be copied from a calendar-style app (possibly RsyncUI) and are unused in a photo culling context.

**Fix:** Delete the unused methods to reduce maintenance surface. Confirm with a project-wide `grep` for each symbol before removal.

---

## Trivial

### T1 — Duplicate file header comments
**Files:** `Actors/ScanFiles.swift`, `Extensions/ThumbnailError.swift`

The file header comment block is duplicated verbatim at the top of each file. Remove the duplicate block.

---

### T2 — `DiscardableThumbnail` — `@unchecked Sendable` with `NSImage` lacks documentation
**File:** `Model/Cache/DiscardableThumbnail.swift`

`NSImage` is not `Sendable`. The `@unchecked Sendable` conformance is safe in practice (`image` is `let`; all `NSDiscardableContent` methods are lock-protected), but the reasoning is not documented in the code.

**Fix:** Add a comment explaining why this is safe:
```swift
// @unchecked Sendable is safe here: `image` is immutable (let) and NSImage
// supports concurrent reads after creation. All NSDiscardableContent protocol
// methods are protected by OSAllocatedUnfairLock.
final class DiscardableThumbnail: NSObject, NSDiscardableContent, @unchecked Sendable {
```

---

### T3 — Global singleton dependencies hinder test isolation
**Files:** `Actors/ScanAndCreateThumbnails.swift`, `Actors/ExtractAndSaveJPGs.swift`

Both actors hard-reference `SharedMemoryCache.shared` and `SettingsViewModel.shared`. Tests run in the same process share cache state between test cases unless explicitly cleared.

**Fix (long-term):** Inject dependencies via `init` parameters with default values pointing to the shared singletons:
```swift
actor ScanAndCreateThumbnails {
    private let memoryCache: SharedMemoryCache
    private let settings: SettingsViewModel

    init(
        memoryCache: SharedMemoryCache = .shared,
        settings: SettingsViewModel = .shared
    ) {
        self.memoryCache = memoryCache
        self.settings = settings
    }
}
```
