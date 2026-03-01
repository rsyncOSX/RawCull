# Concurrency Model — RawCull

> **Branch:** `version-1.1.0`  
> **Files covered:**
> - `RawCull/Model/ViewModels/RawCullViewModel.swift`
> - `RawCull/Actors/ScanAndCreateThumbnails.swift`
> - `RawCull/Actors/ExtractAndSaveJPGs.swift`
> - `RawCull/Views/RawCullView/extension+RawCullView.swift`

---

## Overview

RawCull uses Swift Structured Concurrency (`async`/`await`, `Task`, `TaskGroup`, and `actor`) throughout its two main background operations:

| Operation | Actor | Triggered from |
|---|---|---|
| Scan & create thumbnails | `ScanAndCreateThumbnails` | `RawCullViewModel.handleSourceChange(url:)` |
| Extract & save JPGs | `ExtractAndSaveJPGs` | `extension+RawCullView.extractAllJPGS()` |

Both operations follow the same **two-level task pattern**: an **outer Task** owned by the ViewModel/View layer, and an **inner Task** owned by the actor itself. Cancellation is explicit and must be propagated through both levels.

---

## 1. ScanAndCreateThumbnails

### 1.1 How the task is started

`handleSourceChange(url:)` in `RawCullViewModel` is the entry point. It is an `async` function that runs on `@MainActor`.

```
RawCullViewModel.handleSourceChange(url:)   ← @MainActor async
```

**Step-by-step flow:**

1. **Guard against duplicate processing** — A `processedURLs: Set<URL>` set prevents re-scanning a catalog URL that has already been processed in the current session. If the URL is already in the set, the thumbnail creation block is skipped entirely.

2. **Settings fetch** — Before creating the actor, settings are fetched via `await SettingsViewModel.shared.asyncgetsettings()`. This provides the `thumbnailSizePreview` value used as the rendering target size.

3. **FileHandlers are built** — `CreateFileHandlers().createFileHandlers(...)` bundles three `@MainActor`-bound closures:
   - `fileHandler(_:)` — updates `progress`
   - `maxfilesHandler(_:)` — sets `max`
   - `estimatedTimeHandler(_:)` — sets `estimatedSeconds`

4. **Actor instantiation** — A fresh `ScanAndCreateThumbnails()` actor is created and the handlers are injected via `await actor.setFileHandlers(handlers)`.

5. **Actor reference is stored** — `currentPreloadActor = actor` is assigned on `@MainActor` before the outer Task is launched. This is the handle used later by `abort()`.

6. **Outer Task is created and stored:**
   ```swift
   preloadTask = Task {
       await actor.preloadCatalog(at: url, targetSize: thumbnailSizePreview)
   }
   ```
   This is an **unstructured `Task`** with no explicit actor context, created while on `@MainActor`. It immediately hops to the `ScanAndCreateThumbnails` actor when it calls `await actor.preloadCatalog(...)`.

7. **ViewModel awaits completion:**
   ```swift
   await preloadTask?.value
   creatingthumbnails = false
   ```
   The `handleSourceChange` function suspends here. When the outer Task finishes — either by completing normally or by being cancelled — execution resumes and `creatingthumbnails` is set to `false`.

### 1.2 Inside the actor — preloadCatalog

`preloadCatalog(at:targetSize:)` runs **on the `ScanAndCreateThumbnails` actor**.

**Step-by-step:**

1. **Ensure setup is complete** — `await ensureReady()` is called first. This uses a `setupTask: Task<Void, Never>?` pattern to guarantee that `SharedMemoryCache.shared.ensureReady()` and `getSettings()` are run exactly once, even if `preloadCatalog` is called concurrently.

2. **Cancel any prior inner task** — `cancelPreload()` is called immediately, which cancels and nils out any previously stored `preloadTask` on the actor.

3. **Create the inner Task:**
   ```swift
   let task = Task<Int, Never> {
       // reset counters
       successCount = 0
       processingTimes = []
       lastItemTime = nil
       lastEstimatedSeconds = nil

       let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
       totalFilesToProcess = urls.count
       await fileHandlers?.maxfilesHandler(urls.count)

       return await withTaskGroup(of: Void.self) { group in
           ...
       }
   }
   preloadTask = task           // stored as actor-isolated state
   return await task.value      // actor suspends here
   ```
   This inner `Task<Int, Never>` runs on the actor's context. All mutations to actor-isolated state (`successCount`, `processingTimes`, `cacheMemory`, etc.) happen safely because every child task calls back into the actor via `await self.processSingleFile(...)`.

4. **Controlled concurrency with TaskGroup:**
   ```swift
   let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

   for (index, url) in urls.enumerated() {
       if Task.isCancelled {
           group.cancelAll()
           break
       }
       if index >= maxConcurrent {
           await group.next()   // back-pressure: wait for a slot
       }
       group.addTask {
           await self.processSingleFile(url, targetSize: targetSize, itemIndex: index)
       }
   }
   await group.waitForAll()
   return successCount
   ```
   The loop checks `Task.isCancelled` at the **start of every iteration**. If cancelled, `group.cancelAll()` stops any in-flight child tasks and the loop breaks. `await group.next()` provides back-pressure so no more than `activeProcessorCount * 2` tasks are in flight at once.

5. **Per-file processing** — `processSingleFile(_:targetSize:itemIndex:)` performs multiple `Task.isCancelled` checks at key suspension points:
   - At function entry
   - After the RAM cache check
   - Before the Sony thumbnail extraction
   - **After** the expensive `SonyThumbnailExtractor.extractSonyThumbnail(...)` call (the most critical check — prevents writing stale data after cancellation)

   Cache resolution follows a three-tier lookup:
   - **A. RAM cache** (`SharedMemoryCache.shared`) — synchronous, thread-safe via `NSCache` internal locking
   - **B. Disk cache** (`DiskCacheManager.load(for:)`) — async
   - **C. Extract from source file** — calls `SonyThumbnailExtractor.extractSonyThumbnail(...)`, then normalises to JPEG-backed `NSImage`, stores in RAM, and fires a `Task.detached(priority: .background)` to persist to disk

---

## 2. ExtractAndSaveJPGs

### 2.1 How the task is started

`ExtractAndSaveJPGs` is triggered from `extractAllJPGS()` in `extension+RawCullView.swift`. This function is called from the View layer and is **not** an `async` function itself — it creates an unstructured `Task` to bridge into async code.

```
View (extension+RawCullView) — extractAllJPGS()
  └─ Task {                                           ← outer Task, unstructured, inherits @MainActor
         viewModel.creatingthumbnails = true
         ...
         viewModel.currentExtractActor = extract      ← stored on ViewModel for cancellation
         await extract.extractAndSaveAlljpgs(from: url)
         viewModel.currentExtractActor = nil          ← cleaned up after completion
         viewModel.creatingthumbnails = false
     }
```

**Step-by-step flow:**

1. **Set UI state** — `viewModel.creatingthumbnails = true` is set immediately (on `@MainActor`).

2. **FileHandlers are built** — Same pattern as `ScanAndCreateThumbnails`: closures for `fileHandler`, `maxfilesHandler`, and `estimatedTimeHandler` are assembled via `CreateFileHandlers().createFileHandlers(...)`.

3. **Actor instantiation** — A fresh `ExtractAndSaveJPGs()` actor is created and handlers are injected via `await extract.setFileHandlers(handlers)`.

4. **Actor reference is stored** — `viewModel.currentExtractActor = extract` is assigned **before** the work begins. This is the handle required for `abort()` to cancel the operation.

5. **Outer Task awaits the actor:**
   ```swift
   await extract.extractAndSaveAlljpgs(from: url)
   ```
   The outer Task suspends here until the extraction completes or is cancelled.

6. **Cleanup** — After the call returns (normally or via cancellation), `viewModel.currentExtractActor = nil` and `viewModel.creatingthumbnails = false` are set.

> **Note:** Unlike `ScanAndCreateThumbnails`, the outer `Task` handle for `ExtractAndSaveJPGs` is **not** stored on the ViewModel (`preloadTask` is only used for thumbnails). Cancellation of the outer task therefore relies solely on `abort()` calling `actor.cancelExtractJPGSTask()`.

### 2.2 Inside the actor — extractAndSaveAlljpgs

`extractAndSaveAlljpgs(from:)` runs **on the `ExtractAndSaveJPGs` actor**.

**Step-by-step:**

1. **Cancel any prior inner task** — `cancelExtractJPGSTask()` is called first, which cancels and nils out any existing `extractJPEGSTask`. This is the same defensive pattern as `ScanAndCreateThumbnails`.

2. **Create the inner Task:**
   ```swift
   let task = Task {
       successCount = 0
       processingTimes = []
       let urls = await DiscoverFiles().discoverFiles(at: catalogURL, recursive: false)
       totalFilesToProcess = urls.count
       await fileHandlers?.maxfilesHandler(urls.count)

       return await withThrowingTaskGroup(of: Void.self) { group in
           ...
       }
   }
   extractJPEGSTask = task       // stored as actor-isolated state
   return await task.value       // actor suspends here
   ```
   Note: `ExtractAndSaveJPGs` uses `withThrowingTaskGroup` (vs. `withTaskGroup` in `ScanAndCreateThumbnails`). Errors from child tasks are silently consumed via `try?`.

3. **Controlled concurrency with ThrowingTaskGroup:**
   ```swift
   let maxConcurrent = ProcessInfo.processInfo.activeProcessorCount * 2

   for (index, url) in urls.enumerated() {
       if Task.isCancelled {
           group.cancelAll()
           break
       }
       if index >= maxConcurrent {
           try? await group.next()   // back-pressure
       }
       group.addTask {
           await self.processSingleExtraction(url, itemIndex: index)
       }
   }
   try? await group.waitForAll()
   return successCount
   ```
   Identical back-pressure and cancellation-check pattern to `ScanAndCreateThumbnails`.

4. **Per-file processing** — `processSingleExtraction(_:itemIndex:)` checks `Task.isCancelled` at two points:
   - At function entry
   - **After** `EmbeddedPreviewExtractor.extractEmbeddedPreview(from:)` returns (the critical check — prevents writing a JPG to disk after cancellation)

   If not cancelled, it calls `await SaveJPGImage().save(image:originalURL:)` and then updates progress and ETA.

---

## 3. Task Ownership and Lifecycle Summary

```
                    ┌─────────────────────────────────────────┐
                    │         RawCullViewModel (@MainActor)   │
                    │                                         │
                    │  currentPreloadActor: ScanAnd...?       │
                    │  currentExtractActor: ExtractAnd...?    │
                    │  preloadTask: Task<Void, Never>?        │
                    └─────────────────────────────────────────┘
                               │                     │
          ┌────────────────────┘                     └────────────────────┐
          ▼                                                               ▼
┌─────────────────────────┐                              ┌──────────────────────────┐
│  ScanAndCreateThumbnails│                              │   ExtractAndSaveJPGs     │
│  (actor)                │                              │   (actor)                │
│                         │                              │                          │
│  preloadTask:           │                              │  extractJPEGSTask:       │
│    Task<Int, Never>?    │                              │    Task<Int, Never>?     │
│         │               │                              │         │                │
│         ▼               │                              │         ▼                │
│  withTaskGroup {        │                              │  withThrowingTaskGroup { │
│    processSingleFile()  │                              │   processSingleExtract() │
│    processSingleFile()  │                              │   processSingleExtract() │
│    ...                  │                              │   ...                    │
│  }                      │                              │  }                       │
└─────────────────────────┘                              └──────────────────────────┘
```

| Layer | Owner | Handle name | Type |
|---|---|---|---|
| Outer Task (thumbnails) | `RawCullViewModel` | `preloadTask` | `Task<Void, Never>?` |
| Inner Task (thumbnails) | `ScanAndCreateThumbnails` | `preloadTask` | `Task<Int, Never>?` |
| Outer Task (JPG extract) | View (`extractAllJPGS`) | _(not stored)_ | `Task<Void, Never>` (fire-and-store pattern) |
| Inner Task (JPG extract) | `ExtractAndSaveJPGs` | `extractJPEGSTask` | `Task<Int, Never>?` |

---

## 4. Cancellation

### 4.1 abort() — the single cancellation entry point

`abort()` is a synchronous function on `RawCullViewModel` (`@MainActor`). It is the **single point** for cancelling both operations simultaneously.

```swift
func abort() {
    // --- ScanAndCreateThumbnails ---
    preloadTask?.cancel()          // (1) cancel the outer Task
    preloadTask = nil
    if let actor = currentPreloadActor {
        Task { await actor.cancelPreload() }  // (2) cancel the inner Task
    }
    currentPreloadActor = nil

    // --- ExtractAndSaveJPGs ---
    if let actor = currentExtractActor {
        Task { await actor.cancelExtractJPGSTask() }  // (3) cancel the inner Task
    }
    currentExtractActor = nil

    creatingthumbnails = false      // (4) reset UI state
}
```

### 4.2 Cancellation of ScanAndCreateThumbnails — detailed propagation

```
abort()
  │
  ├─ (1) preloadTask?.cancel()
  │       └─ The outer Task<Void, Never> created in handleSourceChange is marked cancelled.
  │          Because handleSourceChange is awaiting preloadTask?.value, it unblocks
  │          and execution resumes — but the outer task's closure body does NOT re-run;
  │          the await returns with cancellation.
  │
  └─ (2) Task { await actor.cancelPreload() }
          └─ cancelPreload() runs on the ScanAndCreateThumbnails actor:
               preloadTask?.cancel()    ← cancels the INNER Task<Int, Never>
               preloadTask = nil
               └─ The inner Task's isCancelled flag becomes true.
                    └─ withTaskGroup sees isCancelled == true on next loop iteration:
                         group.cancelAll()   ← propagates to all child tasks
                         break               ← stops adding new tasks
                    └─ In-flight processSingleFile() calls check Task.isCancelled
                       at multiple suspension points and return early.
                    └─ group.waitForAll() completes once all children exit.
                    └─ inner Task returns (with partial successCount).
                    └─ preloadCatalog returns.
                    └─ outer Task body completes (returns Void).
```

**Key detail:** Calling `preloadTask?.cancel()` on the ViewModel's outer `Task<Void, Never>` does **not** automatically cancel the inner `Task<Int, Never>` inside the actor. The outer task wraps a call to `actor.preloadCatalog(...)` — cancelling the outer task sets its `isCancelled` flag but the actor's inner task is completely separate and continues running unless explicitly cancelled. This is why `actor.cancelPreload()` **must** also be called.

### 4.3 Cancellation of ExtractAndSaveJPGs — detailed propagation

```
abort()
  │
  └─ (3) Task { await actor.cancelExtractJPGSTask() }
          └─ cancelExtractJPGSTask() runs on the ExtractAndSaveJPGs actor:
               extractJPEGSTask?.cancel()   ← cancels the INNER Task<Int, Never>
               extractJPEGSTask = nil
               └─ The inner Task's isCancelled flag becomes true.
                    └─ withThrowingTaskGroup sees isCancelled == true on next loop iteration:
                         group.cancelAll()   ← propagates to all child tasks
                         break               ← stops adding new tasks
                    └─ In-flight processSingleExtraction() calls check Task.isCancelled
                       at two suspension points and return early.
                    └─ try? await group.waitForAll() completes.
                    └─ inner Task returns (with partial successCount).
                    └─ outer Task in extractAllJPGS() unblocks:
                         viewModel.currentExtractActor = nil
                         viewModel.creatingthumbnails = false
```

**Key detail:** Because `ExtractAndSaveJPGs` does **not** have an outer `Task` handle stored on the ViewModel (unlike `ScanAndCreateThumbnails` which stores `preloadTask`), there is no outer task to `.cancel()` for this flow. Only the inner task cancel path applies. The outer Task in `extractAllJPGS()` will naturally complete once `extractAndSaveAlljpgs` returns after the inner task is cancelled.

### 4.4 What happens at each isCancelled check point

#### ScanAndCreateThumbnails — processSingleFile

| Check point | What happens on cancellation |
|---|---|
| Entry to `processSingleFile` | Returns immediately — skips all cache lookups and I/O |
| After RAM cache lookup (before disk check) | Returns immediately — skips disk and extract |
| Before `SonyThumbnailExtractor.extractSonyThumbnail(...)` | Returns immediately — skips the expensive extraction |
| After `extractSonyThumbnail` returns | Returns immediately — discards the just-extracted image, **does not** store in cache or write to disk |

#### ExtractAndSaveJPGs — processSingleExtraction

| Check point | What happens on cancellation |
|---|---|
| Entry to `processSingleExtraction` | Returns immediately — skips the embedded preview extraction |
| After `EmbeddedPreviewExtractor.extractEmbeddedPreview(...)` returns | Returns immediately — discards the extracted image, **does not** call `SaveJPGImage().save(...)` |

### 4.5 State reset after cancellation

After `abort()` completes:

| ViewModel property | State |
|---|---|
| `preloadTask` | `nil` |
| `currentPreloadActor` | `nil` |
| `currentExtractActor` | `nil` |
| `creatingthumbnails` | `false` |
| `progress` | unchanged (retains last value) |
| `max` | unchanged (retains last value) |
| `estimatedSeconds` | unchanged (retains last value) |

The `processedURLs` set is **not** cleared by `abort()`. A URL that was partially processed will not be re-scanned if the user selects the same source again. This is intentional — partial thumbnails generated before cancellation remain in the memory and disk caches.

---

## 5. ETA Estimation

Both actors implement a rolling ETA calculation based on recent per-item processing times.

- Estimation begins after a minimum number of items are processed:
  - `ScanAndCreateThumbnails`: after `minimumSamplesBeforeEstimation = 10` items
  - `ExtractAndSaveJPGs`: after `estimationStartIndex = 10` items
- The ETA uses the average of the most recent 10 inter-item intervals.
- The ETA is **only updated downward** — if the new estimate is higher than the previous one, it is discarded. This prevents the ETA counter from jumping upward mid-operation.
- The ETA is reported to the ViewModel via `fileHandlers?.estimatedTimeHandler(_:)`, which sets `viewModel.estimatedSeconds`.

---

## 6. Actor Isolation Guarantees

All mutable state in both actors is **actor-isolated**. Child tasks spawned inside `withTaskGroup` / `withThrowingTaskGroup` call back into the actor via `await self.processSingleFile(...)` / `await self.processSingleExtraction(...)`, serialising all mutations (`successCount`, `processingTimes`, `cacheMemory`, etc.) through the actor.

`SharedMemoryCache` (an `NSCache` wrapper) is accessed synchronously from within both actors. This is safe because `NSCache` is internally thread-safe, and the access is documented accordingly in the code.

Background disk writes in `ScanAndCreateThumbnails` use `Task.detached(priority: .background)` with only value types (`cgImage`, `dcache`) captured — this avoids retaining the actor in the detached task and prevents actor isolation violations.