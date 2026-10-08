# RawCull: concurrency, cancellation and stale-data review

This is a static read. I did not build or run the app. Line numbers refer to files under `RawCull/`.

**Files read:**
- `Model/ViewModels/RawCullViewModel+Catalog.swift`
- `Main/RawCullApp.swift`
- `Model/ParametersRsync/ExecuteCopyFiles.swift`
- `Actors/ScanFiles.swift`
- `Actors/ScanAndCreateThumbnails.swift`
- `Actors/ExtractAndSaveJPGs.swift`
- `Actors/RequestThumbnail.swift`
- `Actors/ThumbnailLoader.swift`
- `Actors/ThumbnailPreloadGate.swift`
- `Actors/SharedMemoryCache.swift`
- `Model/ViewModels/CullingModel.swift`
- `Intelligence/Similarity/RawCullSimilarityFeature.swift`

**Not read in detail:** the AI features (Intelligence/*), the burst-grouping view model code, and the zoom and loupe sessions. For those I only grepped for cancel and `onDisappear` calls.

## Architecture strengths

- **Catalog switching.**
  - `startCatalogLoad` (`+Catalog.swift:9-35`) uses a transition generation counter.
  - It flushes persistence before switching, and reverts the selection if the flush fails.
- **Stale-result guards.**
  - `handleSourceChange` re-checks `isActiveCatalogLoad(url)` and `Task.isCancelled` after every await (lines 112-226).
  - `handleSortOrderChange` (238-258) uses a `sortGeneration` token. It re-validates the catalog, source, order and search text.
  - UI handlers for thumbnail preload are each guarded by `isActiveCatalogLoad` (190-211).
- **Continuation hygiene.** These sites cannot double-resume or leak a continuation:
  - `ThumbnailLoader.acquireSlot` (38-62)
  - `ThumbnailPreloadGate` (28-53)
  - `RequestThumbnail.coalescedRequest` (95-117), with `finishRequest` guarded by a generation UUID (175-188)

  In all three the cancel hop goes back through the actor. `ThumbnailLoader.swift:71-82` hands a slot straight to the next waiter, which prevents over-admission.
- **Request coalescing.** `RequestThumbnail` cancels the shared task only when the last waiter leaves (158-173).
- **Cancellation inside task groups.**
  - `ScanFiles` checks `Task.isCancelled` (127, 137, 159, 170).
  - The preload and export groups use a bounded concurrency window (`ScanAndCreateThumbnails.swift:106-130`).
- **Quit handling.** `AppDelegate.beginTermination` (`RawCullApp.swift:44-82`):
  - uses `.terminateLater`
  - retries the flush
  - offers Retry, Cancel or Quit Without Saving
  - allows only one termination task
- **Persistence.**
  - `CullingModel.scheduleSave` (266-285) debounces and uses a revision counter.
  - There is a corrupt-store archive-and-reset path (309+).
- **Memory pressure.** `SharedMemoryCache.swift:264-300` shrinks or clears caches.
- **Cache identity.** `ThumbnailCacheKey` appears to include file size and mtime (`Model/Cache/ThumbnailCacheKey.swift:36`). That gives implicit invalidation when a file is edited externally. I only saw the `attributesOfItem` call, not the full key.
- **Security-scoped access.** It is refcounted through `RawCullCatalogAccess` and `CopyScopedAccess`. Workers retain their own grant (`RawCullViewModel.swift:195-196`, `+Catalog.swift:65-67`).
- **Crash paths.** A grep of non-test code found no `try!`, `fatalError` or `as!`.

## Critical

None found. The main invariants hold.

## High

### H1. Quitting during a rsync copy doesn't terminate the process
- **Where:**
  - `AppDelegate.applicationShouldTerminate` (`RawCullApp.swift:26-36`) only flushes persistence and calls `stopActiveSecurityScopedAccess()`. It never touches the active `ExecuteCopyFiles`.
  - Only `ExecuteCopyFiles.close()` (`ExecuteCopyFiles.swift:239-243`) calls `activeStreamingProcess?.cancel()`. That is reached only if the view calls it (`CopyFilesView.swift:80`, in `onDisappear`).
- **Effect:**
  - On Cmd-Q with a copy running, whether rsync is cancelled depends on SwiftUI delivering `onDisappear` at termination, which is not guaranteed.
  - A detached rsync child may keep writing after the app exits.
- **Fix:**
  - Keep a registry of the active copy (for example `viewModel.activeCopy`).
  - Call `close()` in `releaseAccess`, or before `reply`.
  - Ideally confirm with the user before quitting mid-copy.

```swift
// AppDelegate.beginTermination: before flush
viewModel.activeCopy?.close()   // SIGTERM rsync and release scopes
```

### H2. `extractAndSavejpgs` isn't cancellable from the caller, and a cancel can be lost
- **Where:** `ExtractAndSaveJPGs.swift:84-126`.
  - `await RawCullCatalogAccess.shared.retainAccess` runs at line 89, before the task exists.
  - `extractJPEGSTask` is set only at line 124.
  - `return await task.value` (125) has no `withTaskCancellationHandler`. `ScanAndCreateThumbnails.preloadCatalog` (134-138) does have one.
- **Effect:**
  - Cancelling the caller's task doesn't stop the export.
  - A `cancelExtraction()` that arrives during the `retainAccess` await finds nothing to cancel, so the whole export runs.
- **Fix:**
  - Create and store the task first.
  - Wrap `await task.value` in `withTaskCancellationHandler { … } onCancel: { task.cancel() }`.
  - Add a `cancelRequested` flag, or a generation counter, that is checked after the `retainAccess` await.

### H3. Reentrancy on shared actor counters in preload and export
- **Where:**
  - `ScanAndCreateThumbnails.preloadCatalog` (87-144) and `extractAndSavejpgs`.
  - Both reset `successCount`, `completedCount`, `processingTimes` and `lastItemTime` inside the new task.
  - Per-file work mutates the same state (`ExtractAndSaveJPGs.swift:137-147`).
- **Effect:**
  - `preloadCatalog` calls `cancelPreload()` and then awaits `DiscoverFiles` and the gate (93-94). A second call can interleave there, so two tasks share and reset the same counters.
  - A cancelled first task keeps mutating state after the second run has reset it.
  - Progress, ETA and the returned counts mix runs.
  - `processSingleExtraction` increments after only a partial cancellation check.
- **Fix:**
  - Give each run a `runID` (UUID) and check it before every counter mutation and handler call.
  - Better, keep per-run state in a local struct or class owned by the task, not shared on the actor.

```swift
let runID = UUID(); currentRun = runID
let task = Task { ... guard currentRun == runID else { return } ... }
extractJPEGSTask = task
return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
```

## Medium

### M1. A failed scan is indistinguishable from an empty folder
- **Where:**
  - `ScanFiles.scanFiles` returns `[]` on any directory-listing error (`ScanFiles.swift:179-182`, with the log commented out) and on cancel (170).
  - `handleSourceChange` then takes the `files.isEmpty` branch (`+Catalog.swift:163-172`). It silently resets `currentSelectedSource = nil` and releases access.
- **Effect:** An unmounted volume, a permission problem and a stale bookmark all look like nothing happened. No error is shown.
- **Fix:**
  - Make `scanFiles` `throws` or return `Result`.
  - Show a banner or alert with `error.localizedDescription`.
  - Use a distinct empty state for "no ARW files in this folder".

### M2. Early returns in `handleSourceChange` can leave `scanning == true`
- **Where:**
  - `+Catalog.swift:156-158` returns when `hydrateCatalog` is false while the load is still active.
  - `hydrateCatalog` is false both when the catalog identity changed and when the child task was cancelled by `cancelHydration`. For non-cancel failures the spinner never ends.
  - Line 175, `guard cullingModel.loadSavedFiles() else { return }`, runs after `scanning = false` and skips the thumbnail preload. No error is shown from this site. I did not check whether `persistenceLoadFailure` is surfaced elsewhere.
- **Fix:**

```swift
defer { if isActiveCatalogLoad(url) { scanning = false } }
```

### M3. `ScanFiles` spawns one child task per file with no cap
- **Where:** `ScanFiles.swift:126-156`. The loop adds every file without `group.next()` throttling, unlike the preload and export groups.
- **Effect:** For large folders this means thousands of simultaneous header reads (`rawLoader.fileMetadata`), unless the loader gates them internally. I did not verify that.
- **Fix:** Use the same bounded-window pattern: `if index >= limit { await group.next() }`.

### M4. Progress callbacks are unordered fire-and-forget Tasks
- **Where:**
  - `ScanFiles.swift:135`
  - `ScanAndCreateThumbnails.swift:252, 258, 278`
  - `ScanAndExtractJPGs.swift:134, 152`
- **Effect:** Main-actor hops can reorder, so a lower count can overwrite a higher one. They also run after the scan has finished. The `isActiveCatalogLoad` guard prevents cross-catalog bleed but not the ordering problem.
- **Fix:** Apply `max(old, new)` on the receiver, or use an `AsyncStream` consumed on the main actor.

### M5. No detection of external file or volume changes
- **Evidence:** A grep for FSEvents, `NSFilePresenter`, file `DispatchSource` and unmount notifications finds only the memory-pressure source.
- **Effect:**
  - `processedURLs` (`RawCullViewModel.swift:210`, checked at `+Catalog.swift:186`) is never invalidated. Revisiting a folder skips the preload even if files were added, removed or replaced.
  - `files` can contain deleted files, so loaders return nil and the UI shows blanks.
  - Orphaned disk-cache entries are only pruned by age.
- **Fix:**
  - Observe `NSWorkspace.didUnmountNotification`. Cancel and reset when the active catalog's volume goes away.
  - Add a directory watcher, or rescan on app activation. Compare file count and mtimes before skipping preload.
  - Track which files were actually preloaded, rather than a Set of URLs.

### M6. `try?` hides why a copy failed to start
- **Where:** `ExecuteCopyFiles.swift:165, 174`. `try? bookmarkStore.acquireSource/acquireDestination` discards the error, so every failure maps to the generic `.sourceAccessFailed` or `.destinationAccessFailed`.
- **Effect:** A stale bookmark (`CopyBookmarkStore.swift:94-102`), a missing volume and a revoked permission look the same to the user.
- **Fix:** Use `do/catch` and carry the underlying error in `CopyStartupFailure`.

### M7. `close()` releases resources before rsync has exited
- **Where:** `ExecuteCopyFiles.swift:239-243`. `close()` sets `isClosing`, calls `cancel()`, then runs `cleanup()` immediately. Cleanup releases scoped access and deletes the include file. The termination callback (252-259) is a fire-and-forget Task.
- **Effect:** A narrow window where rsync still reads `--files-from` or writes after the scope is released. This is low in practice because `cancel()` normally sends SIGTERM first.
- **Fix:** Defer `cleanup()` to the termination callback, with a timeout fallback.

## Low

- **L1. Memory-pressure source tasks.**
  - Unstructured `Task { await self… }` in the `DispatchSource` handlers (`SharedMemoryCache.swift:240-296`) can reorder.
  - For example, `.normal`'s `refreshConfig` could overtake a later `.critical`.
  - Serialise events, or read `source.data` inside the actor on each event.
- **L2. Detached work isn't cancel-aware.**
  - Sites: `ScanFiles.swift:192`, `ScanAndCreateThumbnails.swift:241`, `MemoryViewModel.swift:57`.
  - The JSON read is short, so this is cosmetic.
  - A cancelled catalog still writes its disk-cache thumbnail, which is arguably desirable.
- **L3. Untracked cancel tasks.**
  - `Task { await actor.cancelPreload() }` (`+Catalog.swift:97, 102`) and the `onCancel` hops are untracked.
  - On quit, the app can exit before they run.
  - `preloadTask?.cancel()` also runs synchronously, so the impact is small.
- **L4. `try?` in caches and persistence.** Mostly best-effort cleanup:
  - `PerFileAnalysisArtifactStore.swift:138, 149, 156, 161, 310, 348`
  - `BurstAnalysisCache.swift:231-232, 293`
  - `DiskCacheManager.swift:77, 132, 160`
  - `FullSizeJPGDiskCache.swift:35, 70`

  Two deserve attention:
  - `PerFileAnalysisArtifactStore.swift:156` (`try? encode(record).write`) silently loses analysis results on a full disk.
  - `RawCullAIModelRuntime.swift:93` (`try? ObjectMaskDiskStore(...)`) silently disables a feature.

  Log with `Logger.warning` and surface disk-full conditions once.
- **L5. Settings decoding fallbacks.** Per-field `try?` with defaults (`SettingsViewModel.swift:400-422`) is reasonable, but corrupt values are replaced silently.
- **L6. `@unchecked Sendable` types.**
  - `CachedThumbnail.swift:19` and `TrackedThumbnailCache.swift:9` rely on NSCache thread safety and immutability.
  - That is acceptable if the stored `CGImage` is never mutated. Document the invariant.
- **L7. `DispatchQueue.main.async` in views.**
  - Sites: `ImageTableVerticalView.swift:64`, `BurstCullingWorkspaceView.swift:334`, `AIAnalysisView.swift:242`.
  - Consider `Task { @MainActor in }` for consistency. I did not check whether they are real hazards.
- **L8. Debug-only reset helper.** `resetForTesting` (`SharedMemoryCache.swift:373-387`) is `#if DEBUG`, so it is fine.

## Suggested fix order

1. H1
2. H2
3. H3
4. M1 and M2, which are user-visible
5. M5
6. M3, M4 and M6
7. M7 and the Low items
