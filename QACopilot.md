# Static Analysis Report — RawCull

Fails (❌) and Warnings (⚠️) are updated and marked with a ~~strikethrough~~ in the summarized [chapter 16](#16-summary--priority-backlog) when fixed.

> **Report date:** 2026-03-01
> **Analysed by:** GitHub Copilot (exhaustive static analysis)
> **Repository:** https://github.com/rsyncOSX/RawCull
> **Primary language:** Swift 6 — macOS, SwiftUI + AppKit
> **Tooling in repo:** SwiftLint · SwiftFormat · Periphery

Each finding is classified as:
- ✅ **PASS** — meets expectation
- ⚠️ **WARN** — works, but has a known weakness worth addressing
- ❌ **FAIL** — concrete defect or anti-pattern that should be fixed
- ℹ️ **INFO** — neutral observation / design note

---

## Table of Contents

1. [Repository Layout & Module Structure](#1-repository-layout--module-structure)
2. [Architecture & MVVM Boundaries](#2-architecture--mvvm-boundaries)
3. [Swift Concurrency Model](#3-swift-concurrency-model)
4. [Thumbnail Pipeline & Caching](#4-thumbnail-pipeline--caching)
5. [File Scanning & EXIF Metadata](#5-file-scanning--exif-metadata)
6. [Persistence Layer (JSON / Culling)](#6-persistence-layer-json--culling)
7. [rsync Integration (Copy Pipeline)](#7-rsync-integration-copy-pipeline)
8. [Error Handling & Logging](#8-error-handling--logging)
9. [SwiftUI View Layer](#9-swiftui-view-layer)
10. [Memory Management & Memory Pressure](#10-memory-management--memory-pressure)
11. [Security & Sandbox Entitlements](#11-security--sandbox-entitlements)
12. [Naming & API Design](#12-naming--api-design)
13. [Tooling Configuration](#13-tooling-configuration)
14. [Test Suite](#14-test-suite)
15. [Build & Distribution Pipeline](#15-build--distribution-pipeline)
16. [Summary & Priority Backlog](#16-summary--priority-backlog)

---

## 1. Repository Layout & Module Structure

### Directory tree (as of 2026-03-01)

```
RawCull/
  Actors/         — Swift actors: ScanFiles, DiskCacheManager, SharedMemoryCache,
                    ScanAndCreateThumbnails, RequestThumbnail, ExtractAndSaveJPGs,
                    DiscoverFiles, SaveJPGImage, ActorCreateOutputforView
  Enum/           — Stateless helpers: SonyThumbnailExtractor, EmbeddedPreviewExtractor
  Extensions/     — extension+String+Date.swift, extension+Thread+Logger.swift
  Main/           — RawCullApp.swift  (entry point, SupportedFileType, WindowIdentifier)
  Model/
    ARWSourceItems/  — FileItem, ARWSourceCatalog
    Cache/           — CacheConfig, CacheDelegate, DiscardableThumbnail
    ParametersRsync/ — ExecuteCopyFiles, ArgumentsSynchronize, RsyncProcessStreaming, …
    ViewModels/      — RawCullViewModel, CullingModel, SettingsViewModel,
                       GridThumbnailViewModel
  Views/
    CacheStatistics/ — CacheStatisticsView
    CopyFiles/       — CopyFilesView
    FileViews/       — FileContentView, FileDetailView, FileInspectorView
    GridView/        — GridThumbnailView, GridThumbnailSelectionView
    Modifiers/       — ButtonStyles
    RawCullView/     — RawCullView, extension+RawCullView, RawCullAlertView,
                       RawCullSheetContent
    Settings/        — SettingsView, CacheSettingsTab, ThumbnailSizesTab, MemoryTab
RawCullTests/
  ThumbnailProviderTests.swift
  ThumbnailProviderAdvancedTests.swift
  ThumbnailProviderCustomMemoryTests.swift
```

| ID | Finding | Status |
|---|---|---|
| LAYOUT-001 | Source tree is well-partitioned: Actors / Enum / Model / Views separation is consistent and idiomatic for a macOS SwiftUI app. | ✅ PASS |
| ~~LAYOUT-002~~ | `SupportedFileType` and `WindowIdentifier` enums live in `RawCullApp.swift` rather than their own files, mixing app-entry concerns with domain types. | ⚠️ WARN |
| ~~LAYOUT-003~~ | `ThumbnailError` is defined inside `RequestThumbnail.swift` (indicated by comment header `ThumbnailError.swift`). It is used by `DiskCacheManager` and `SonyThumbnailExtractor` — cross-file type dependency hidden inside a single file. | ⚠️ WARN |
| LAYOUT-004 | No `Package.swift` / Swift Package Manager manifest. The project is pure Xcode. Acceptable for a macOS-only app, but limits library extraction later. | ℹ️ INFO |

---

## 2. Architecture & MVVM Boundaries

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| ARCH-001 | MVVM separation is clear. Views are thin; ViewModels own observable state; background work is isolated in actors. | ✅ PASS | `RawCullViewModel`, `RawCull/Actors/` | Overall structure is consistent. |
| ARCH-002 | `RawCullViewModel` is `@Observable @MainActor`. All UI-mutating state (`files`, `progress`, `scanning`, …) is main-actor-bound. | ✅ PASS | `RawCull/Model/ViewModels/RawCullViewModel.swift` | Correct isolation. |
| ARCH-003 | `ExecuteCopyFiles` is `@Observable @MainActor` and correctly confines its UI-facing callbacks to the main actor. | ✅ PASS | `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift` | Good. |
| ~~ARCH-004~~ | `CullingModel` is now `@Observable @MainActor` — threading contract is explicit and enforced. | ✅ FIXED | `RawCull/Model/ViewModels/CullingModel.swift` L5 | Fixed. |
| ~~ARCH-005~~ | `GridThumbnailViewModel` is `@Observable @MainActor`. Holds references to `RawCullViewModel` and `CullingModel` — creates an optional cross-ViewModel reference that must be set before use. No guard against use-before-set (nil-crash path). | ⚠️ WARN | `RawCull/Model/ViewModels/GridThumbnailViewModel.swift` | Consider a precondition or Result type. |
| ARCH-006 | `SettingsViewModel.shared` is a `@MainActor` singleton accessed via `await SettingsViewModel.shared.asyncgetsettings()` from non-main-actor code. This is correct but means actors must always `await` to read settings, adding latency. | ℹ️ INFO | `RawCull/Model/ViewModels/SettingsViewModel.swift` | Not a defect; note for future optimisation. |
| ARCH-007 | `FileHandlers` is injected into actors via `setFileHandlers(_:)`. This is a good dependency-injection pattern and aids testability. | ✅ PASS | `ScanAndCreateThumbnails`, `ExtractAndSaveJPGs` | Keep consistent. |
| ~~ARCH-008~~ | `abort()` in `RawCullViewModel` is now fully implemented: cancels `preloadTask`, calls `actor.cancelPreload()` and `actor.cancelExtractJPGSTask()`, and resets state. | ✅ FIXED | `RawCull/Model/ViewModels/RawCullViewModel.swift` L187-205 | Fixed. |

---

## 3. Swift Concurrency Model

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| CONC-001 | Heavy I/O and CPU work (scanning, thumbnail extraction, disk cache) isolated to actors off the main thread. | ✅ PASS | `RawCull/Actors/` | Good isolation. |
| ~~CONC-002~~ | `DiscoverFiles.discoverFiles` uses `Task.detached { [self] in … }` and reads `self.supported` inside the detached closure. Because `supported` is `nonisolated let`, this compiles without warning but technically crosses actor isolation for a constant. In strict concurrency it can trigger warnings. | ⚠️ WARN | `RawCull/Actors/DiscoverFiles.swift` L15-28 | Copy `supported` to a local `let` before the detached block for clarity. |
| CONC-003 | `ScanAndCreateThumbnails.preloadCatalog` and `ExtractAndSaveJPGs.extractAndSaveAlljpgs` both check `Task.isCancelled` at the start of each iteration and call `group.cancelAll()`. | ✅ PASS | `ScanAndCreateThumbnails.swift`, `ExtractAndSaveJPGs.swift` | Correct cancellation propagation. |
| CONC-004 | `DiskCacheManager.load` and `.save` use `Task.detached` with explicit priority, capturing only value types (`fileURL`, `cgImage`), preventing the actor from being retained. | ✅ PASS | `RawCull/Actors/DiskCacheManager.swift` | Good pattern. |
| CONC-005 | `SharedMemoryCache.memoryCache` (`NSCache`) is declared `nonisolated(unsafe) let`. This is correct because `NSCache` is internally thread-safe. The code comment explains the rationale. | ✅ PASS | `RawCull/Actors/SharedMemoryCache.swift` L35 | Well-documented. |
| CONC-006 | `CacheDelegate._evictionCount` uses `nonisolated(unsafe) var` protected by an `NSLock`. This is safe but low-level. | ✅ PASS | `RawCull/Model/Cache/CacheDelegate.swift` | Acceptable; consider `OSAllocatedUnfairLock` (already used in `DiscardableThumbnail`) for consistency. |
| CONC-007 | `RawCullView` uses `.task(id: viewModel.selectedSource)` for source changes (auto-cancels the outer task), but still wraps the actual work in an inner `Task(priority: .background)` at L138-143. This inner unstructured task is **not** cancelled when `.task(id:)` fires for a new source — the race condition from the original finding is only partially mitigated. | ⚠️ WARN | `RawCull/Views/RawCullView/RawCullView.swift` L137-143 | Remove the inner `Task { … }` wrapper and call `await viewModel.handleSourceChange(url:)` directly inside the `.task(id:)` body, which is already async and auto-cancellable. |
| CONC-008 | `ExtractAndSaveJPGs.extractAndSaveAlljpgs` wraps work in an unstructured `Task { … }` stored as `extractJPEGSTask`. This is correct but it means the inner task inherits the actor's isolation and all `self.` mutations within run on the actor. Verify that large loops in this task do not stall the actor. | ⚠️ WARN | `RawCull/Actors/ExtractAndSaveJPGs.swift` L33 | Consider structured `withTaskGroup` directly on the actor function signature instead. |
| CONC-009 | `SettingsViewModel.loadSettings()` is called from `init()` inside a `Task { await loadSettings() }`. If `SettingsViewModel.shared` is accessed before that task completes, default values will be returned. There is no synchronisation guard against this race. | ⚠️ WARN | `RawCull/Model/ViewModels/SettingsViewModel.swift` L22-24 | Use a `setupTask` pattern (already used in `SharedMemoryCache`) to serialise first-access. |
| CONC-010 | `@preconcurrency import AppKit` and `@preconcurrency import ImageIO` are used in `EmbeddedPreviewExtractor.swift` and `SaveJPGImage.swift`. This suppresses warnings without fully adopting strict sendability for those types. | ⚠️ WARN | `RawCull/Actors/SaveJPGImage.swift`, `RawCull/Enum/EmbeddedPreviewExtractor.swift` | Track and remove `@preconcurrency` when Apple adopts strict concurrency annotations for those frameworks. |
| CONC-011 | `SonyThumbnailExtractor.extractSonyThumbnail` manually dispatches to `DispatchQueue.global` via `withCheckedThrowingContinuation` to avoid blocking the calling actor. This is correct but can be simplified with `async` on the extraction work directly (requires macOS 15+ `@concurrent` or explicit nonisolated). | ℹ️ INFO | `RawCull/Enum/SonyThumbnailExtractor.swift` L27-38 | Works correctly; note for future simplification. |
| CONC-012 | `RawCullViewModel.handleSourceChange` creates a new `ScanFiles()` actor instance for scanning and another for sorting (L96, L103), then both are abandoned after the call. Creating short-lived actor instances for every source change is wasteful; actors carry internal state and dispatch queues. | ⚠️ WARN | `RawCull/Model/ViewModels/RawCullViewModel.swift` L96-107 | Consider making `ScanFiles` a stored property of `RawCullViewModel` or a shared singleton, and reuse across calls. |
| CONC-013 | `RawCullView.body` calls `viewModel.scanning.toggle()` (L140) immediately before `handleSourceChange(url:)`, which itself sets `scanning = true` (L94). If `scanning` was already `true` when the `.task(id:)` fires, the toggle sets it to `false`, and the subsequent assignment to `true` inside `handleSourceChange` is correct — but the double-set is fragile and misleading. | ⚠️ WARN | `RawCull/Views/RawCullView/RawCullView.swift` L140 | Remove the `viewModel.scanning.toggle()` call from the view and let `handleSourceChange` own the `scanning` state exclusively. |

---

## 4. Thumbnail Pipeline & Caching

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| CACHE-001 | Layered lookup order is correct: RAM (`NSCache`) → Disk → Live extraction. | ✅ PASS | `RawCull/Actors/RequestThumbnail.swift` resolveImage() | Correct. |
| CACHE-002 | Disk cache key is MD5 of the standardized file path. MD5 is appropriate for non-security-sensitive keying. Key space is flat (no subdirectory sharding). | ✅ PASS | `RawCull/Actors/DiskCacheManager.swift` cacheURL() | Acceptable. |
| CACHE-003 | **No file-modification-date check when loading from disk cache.** If the source ARW file is replaced or edited after caching, the stale JPEG thumbnail will be served indefinitely. | ❌ FAIL | `DiskCacheManager.load()` — no mtime comparison | Add `contentModificationDateKey` check: if source mtime > cache mtime, invalidate. |
| CACHE-004 | Disk cache pruning (`pruneCache(maxAgeInDays:)`) **exists** in `DiskCacheManager` and is exposed via `SharedMemoryCache.pruneDiskCache(maxAgeInDays:)` and the Settings UI "Prune Disk Cache" button. | ✅ PASS | `DiskCacheManager.pruneCache`, `CacheSettingsTab` | Pruning is implemented. |
| CACHE-005 | Disk cache has no **maximum size cap** in addition to age-based pruning. A user who never manually prunes could accumulate many GBs of cached thumbnails. | ⚠️ WARN | `DiskCacheManager` | Add a size-based eviction path (e.g., prune oldest files when total size exceeds a configurable threshold). |
| CACHE-006 | `DiscardableThumbnail` correctly implements `NSDiscardableContent` with an `OSAllocatedUnfairLock`-guarded `(isDiscarded, accessCount)` pair. `beginContentAccess` / `endContentAccess` / `discardContentIfPossible` are all correctly implemented. | ✅ PASS | `RawCull/Model/Cache/DiscardableThumbnail.swift` | Excellent implementation. |
| CACHE-007 | Memory cache cost uses actual pixel representation dimensions from `image.representations` with a configurable bytes-per-pixel, plus a 10 % overhead buffer. This is a much more accurate cost model than logical `image.size`. | ✅ PASS | `DiscardableThumbnail.init` | Good. |
| CACHE-008 | `CacheDelegate` tracks eviction counts via `NSCacheDelegate`. Evictions are exposed through `getCacheStatistics()` and shown in the `CacheStatisticsView`. | ✅ PASS | `RawCull/Model/Cache/CacheDelegate.swift` | Good observability. |
| CACHE-009 | Memory pressure monitoring is implemented via `DispatchSourceMemoryPressure`. On `.warning` it reduces the cache to 60 %; on `.critical` it clears all objects. Warnings are surfaced to the UI via `FileHandlers.memorypressurewarning`. | ✅ PASS | `SharedMemoryCache.startMemoryPressureMonitoring()` | Strong. |
| CACHE-010 | `SharedMemoryCache.ensureReady()` uses an `isConfigured` boolean guard. If called concurrently before the first setup completes, two tasks could both read `isConfigured == false` and both proceed to configure. The actor serialises them, but both will call `applyConfig` — the second call being redundant. | ⚠️ WARN | `SharedMemoryCache.ensureReady()` | Use the same `setupTask: Task<Void,Never>?` pattern already used in `ScanAndCreateThumbnails` and `RequestThumbnail`. |
| ~~CACHE-011~~ | `DiskCacheManager.save(_:for:)` now uses `do { try … } catch { Logger.process.warning(…) }` inside a detached task. Write failures are properly logged. | ✅ FIXED | `DiskCacheManager.swift` L51-59 | Fixed. |
| CACHE-012 | Thumbnail JPEG quality for disk cache is hard-coded at `0.7` in `DiskCacheManager.writeImageToDisk`. No setting exposes this to users. | ℹ️ INFO | `DiskCacheManager.swift` L74 | Acceptable default; consider adding to settings if quality complaints arise. |
| CACHE-013 | `SonyThumbnailExtractor` and `EmbeddedPreviewExtractor` are both used, serving different purposes (preview vs. full-size extraction). The naming could imply they are Sony-specific. `EmbeddedPreviewExtractor` is the generic path; both correctly use `CGImageSourceCreateThumbnailAtIndex`. | ℹ️ INFO | `RawCull/Enum/` | Consider renaming `SonyThumbnailExtractor` → `RAWThumbnailExtractor` for clarity. |
| CACHE-014 | `SharedMemoryCache.updateCacheDisk()` at L317-320 logs "found in RAM Cache" — a copy-paste error from `updateCacheMemory()`. The misleading log message makes it impossible to distinguish RAM hits from disk hits in diagnostics. | ⚠️ WARN | `RawCull/Actors/SharedMemoryCache.swift` L318 | Change log string to "found in Disk Cache (misses: …)". |

---

## 5. File Scanning & EXIF Metadata

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| SCAN-001 | `ScanFiles.scanFiles` correctly calls `startAccessingSecurityScopedResource()` and wraps the scope in a `defer` statement. | ✅ PASS | `RawCull/Actors/ScanFiles.swift` L27-28 | Correct sandbox handling. |
| SCAN-002 | Directory enumeration uses `.skipsHiddenFiles`. | ✅ PASS | `ScanFiles.scanFiles` L42 | Good. |
| SCAN-003 | File filtering is limited to `.arw` extension only (L49), despite `SupportedFileType` listing `arw`, `tiff`, `tif`, `jpeg`, `jpg`. `ScanFiles` hard-codes only ARW. | ❌ FAIL | `ScanFiles.swift` L49 | Either remove unused enum cases or use `SupportedFileType.allCases.map { $0.rawValue }` for the extension filter to keep declaration and behaviour in sync. |
| ~~SCAN-004~~ | `extractExifData` is now called inside a `withTaskGroup` child task (L60), running concurrently across all discovered files. EXIF extraction no longer serially blocks the actor. | ✅ FIXED | `RawCull/Actors/ScanFiles.swift` L55-70 | Fixed. |
| SCAN-005 | EXIF extraction failure returns `nil` without any logging. | ⚠️ WARN | `ScanFiles.extractExifData` L108-114 | Add `Logger.process.debug("extractExifData: no EXIF at \(url.lastPathComponent)")` for diagnostics. |
| SCAN-006 | `ScanFiles.sortFiles` is `@concurrent nonisolated` — it correctly runs off-actor, which is good for performance on large catalogs. | ✅ PASS | `ScanFiles.sortFiles` L90-103 | Good. |
| SCAN-007 | `DiscoverFiles.discoverFiles` does not call `startAccessingSecurityScopedResource()` even though it operates on user-selected URLs. It is always called with catalogs already opened by `ScanFiles` or `ScanAndCreateThumbnails`. This indirect dependency is not documented. | ⚠️ WARN | `RawCull/Actors/DiscoverFiles.swift` | Add a comment or assertion clarifying that callers must hold the security-scoped resource. |

---

## 6. Persistence Layer (JSON / Culling)

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| PERS-001 | `CullingModel` persists tagged/rated file records to JSON via `WriteSavedFilesJSON` and reads via `ReadSavedFilesJSON`. This is a straightforward approach for an app of this scale. | ✅ PASS | `CullingModel.swift` | Simple and appropriate. |
| PERS-002 | `WriteSavedFilesJSON` is called synchronously on the main actor inside `CullingModel.toggleSelectionSavedFiles`. Now that `CullingModel` is `@MainActor`, this is safe from a threading perspective, but a large `savedFiles` array could still introduce perceptible latency on the main thread during JSON serialisation. | ⚠️ WARN | `CullingModel.toggleSelectionSavedFiles` L83 | Dispatch the write to a `Task.detached` background task for large catalogs. |
| ~~PERS-003~~ | `CullingModel` is now `@Observable @MainActor`. All mutations and reads are on the main actor; the data race is eliminated. | ✅ FIXED | `RawCull/Model/ViewModels/CullingModel.swift` L5 | Fixed. |
| PERS-004 | `SettingsViewModel.loadSettings()` and `saveSettings()` both call `FileManager.default.createDirectory` on the calling context. `loadSettings` is called from `init` inside a `Task`, so directory creation may race with first access. | ⚠️ WARN | `SettingsViewModel.swift` | Ensure directory creation is serialised (the `Task` pattern already helps, but `saveSettings` can be called independently). |
| PERS-005 | `SettingsViewModel.validateSettings()` exists but its contents were not visible in the analysed excerpt. Confirm it clamps all values to sane ranges before saving. | ℹ️ INFO | `SettingsViewModel.saveSettings` | Verify completeness. |

---

## 7. rsync Integration (Copy Pipeline)

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| RSYNC-001 | `ExecuteCopyFiles` is `@Observable @MainActor` and holds `weak var sidebarRawCullViewModel: RawCullViewModel?`. Using `weak` prevents retain cycles. | ✅ PASS | `ExecuteCopyFiles.swift` L20 | Correct. |
| RSYNC-002 | Security-scoped resources for source and destination folders are accessed via bookmark keys (`sourceBookmark`, `destBookmark`) with a path fallback. The lifetime is managed with `sourceAccessedURL`/`destAccessedURL` stored on the object. | ✅ PASS | `ExecuteCopyFiles.startcopyfiles` | Correct pattern. |
| ~~RSYNC-003~~ | `ArgumentsSynchronize` builds the rsync argument list. The `--include-from=` parameter path is a Documents-directory file (`copyfilelist.txt`). This file is written synchronously on the main actor immediately before the process starts, which is fine for single invocations but could race if two copy operations were triggered rapidly. The UI already enforces single-operation-at-a-time via `executionManager` state. | ✅ PASS | `ExecuteCopyFiles.startcopyfiles` L52 | Single-operation enforcement is in place. |
| RSYNC-004 | The filter file is written to `Documents/copyfilelist.txt` — a fixed path. If the app is running multiple simultaneous copy operations (not currently possible, but worth noting), they would collide on this file. | ℹ️ INFO | `ExecuteCopyFiles.savePath` | Document that only one copy operation is supported at a time. |
| RSYNC-005 | `RsyncProcessStreaming` is used for streaming output. Progress updates call back via `onProgressUpdate` and `onCompletion` closures, which dispatch to `@MainActor`. | ✅ PASS | `ExecuteCopyFiles.startcopyfiles` | Good streaming pattern. |
| RSYNC-006 | Failure path of `process.executeProcess()` calls `Logger.process.errorMessageOnly` and then `Task { @MainActor in self.cleanup() }`. The error is logged but **not surfaced to the user** (no alert or completion callback with error). | ⚠️ WARN | `ExecuteCopyFiles.startcopyfiles` L120-125 | Call `onCompletion` with an error result so the UI can inform the user. |

---

## 8. Error Handling & Logging

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| ERR-001 | `ThumbnailError` is a typed `LocalizedError` with meaningful `errorDescription` values for `invalidSource`, `generationFailed`, and `contextCreationFailed`. | ✅ PASS | `RequestThumbnail.swift` | Good. |
| ERR-002 | `DiskCacheManager.init()` uses `do { try … } catch { Logger.process.warning(…) }` for directory creation. | ✅ PASS | `DiskCacheManager.swift` L14-19 | Correct error handling. |
| ~~ERR-003~~ | `DiskCacheManager.save()` now uses `do { try … } catch { Logger.process.warning(…) }` — write failures are properly logged. | ✅ FIXED | `DiskCacheManager.swift` L54-58 | Fixed. |
| ERR-004 | `SettingsViewModel.saveSettings()` and `loadSettings()` both use `do/catch` with `Logger.process.errorMessageOnly`. | ✅ PASS | `SettingsViewModel.swift` | Good. |
| ERR-005 | `Logger.process.errorMessageOnly` and `debugMessageOnly` are `#if DEBUG` gated — errors are **not logged in Release builds**. This means production users and crash reporters cannot see error messages from these calls. | ❌ FAIL | `extension+Thread+Logger.swift` L29-33 | `errorMessageOnly` should use `os_log` at `.error` level unconditionally. Only `debugMessageOnly` and `debugThreadOnly` should be `#if DEBUG` gated. |
| ERR-006 | Memory pressure handler logs only at `debug` level (`Logger.process.debugMessageOnly`). Critical pressure events (cache cleared) should be logged at `.warning` or `.error` unconditionally. | ⚠️ WARN | `SharedMemoryCache.logMemoryPressure` L241-243 | Use `Logger.process.warning(…)` for `.warning` and `.critical` events. |
| ERR-007 | `ScanFiles.scanFiles` logs scan errors at `.warning`. | ✅ PASS | `ScanFiles.swift` L85 | Good. |
| ERR-008 | `EmbeddedPreviewExtractor` logs at `.warning` for missing image source and missing JPEG, and at `.info` for normal decode paths. Appropriate levels. | ✅ PASS | `EmbeddedPreviewExtractor.swift` | Good. |
| ERR-009 | `SaveJPGImage.save` logs both success and failure via `Logger.process.info` and `Logger.process.error`. However, `.error` calls are guarded by `#if DEBUG` via `errorMessageOnly`. Same issue as ERR-005. | ❌ FAIL | `SaveJPGImage.swift` L35-42 | Use unconditional `Logger.process.error(…)` for the failure path. |

---

## 9. SwiftUI View Layer

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| UI-001 | Root navigation uses `NavigationSplitView` with sidebar / content / detail columns — idiomatic for macOS. | ✅ PASS | `RawCullView.swift` | Good. |
| UI-002 | `SettingsView` and all settings tabs receive `SettingsViewModel` via `@Environment`. | ✅ PASS | `SettingsView.swift` L10 | Good. |
| ~~UI-003~~ | `RawCullViewModel.handleSourceChange` is now called from `.task(id: viewModel.selectedSource)` which auto-cancels on ID change. The outer task cancellation is correct. See CONC-007 for the remaining inner `Task` concern. | ⚠️ WARN | `RawCullView.swift` L137-143 | Partially fixed; inner `Task` wrapper still present — see CONC-007. |
| UI-004 | `FileContentView` accepts `AnyView` as the `filetableview` parameter, bypassing SwiftUI's type-erasure optimisations. | ⚠️ WARN | `RawCull/Views/FileViews/FileContentView.swift` | Replace with a generic `Content: View` parameter and `@ViewBuilder`. |
| UI-005 | `RawCullAlertView` is a caseless enum used as a namespace for a static factory method. This is an acceptable Swift pattern. | ✅ PASS | `RawCullAlertView.swift` | Fine. |
| UI-006 | `CacheStatisticsView` polls cache stats via an `AsyncStream` timer firing every 5 seconds. The stream is properly cancelled when the task is cancelled via structured concurrency. | ✅ PASS | `CacheStatisticsView.swift` | Good pattern. |
| UI-007 | `MemoryTab` polls memory stats via an `AsyncStream` timer every 1 second. `try? await Task.sleep(nanoseconds:)` inside the stream continuation — a `Task.isCancelled` check exists. However, if `updateMemoryStats()` is synchronous and expensive, it will run on the continuation's thread. | ⚠️ WARN | `MemoryTab.swift` | Verify `updateMemoryStats()` is cheap or dispatch to a background context. |
| UI-008 | `ConditionalGlassButton` contains an `if #available(macOS 26.0, *)` branch. macOS 26 is not yet released (as of 2026-03-01). This is forward-looking code for a beta OS. | ℹ️ INFO | `ButtonStyles.swift` | Fine for development; ensure the fallback branch is fully tested on current macOS. |
| UI-009 | `RawCullView` subscribes to `viewModel.memorypressurewarning` via `.onChange` and starts a `withAnimation(.repeatForever)`. This animation runs indefinitely until dismissed — correct behaviour, but the animation value `memoryWarningOpacity` is never reset to `0.3` after the warning clears. When the warning disappears the overlay is removed, but the `@State` remains at `0.8`, so the next warning flash starts from the wrong baseline. | ⚠️ WARN | `RawCullView.swift` startMemoryWarningFlash() | Reset `memoryWarningOpacity` to `0.3` when `memorypressurewarning` returns to `false`. |
| UI-010 | `RawCullApp.performCleanupTask()` logs a debug message but performs no actual cleanup (no cache flush, no settings save). Given that `SharedMemoryCache` and `SettingsViewModel` hold in-flight state, shutdown is clean only by virtue of OS reclamation. | ⚠️ WARN | `RawCullApp.swift` L98-100 | Consider calling `await SharedMemoryCache.shared.stopMemoryPressureMonitoring()` and `await SettingsViewModel.shared.saveSettings()` on termination. |
| UI-011 | `AppDelegate.applicationWillTerminate` is an empty stub. Cleanup logic in `RawCullApp.performCleanupTask()` is triggered from `.onDisappear` on the main window, which may not fire reliably on forced termination (e.g. `SIGTERM` from the OS). | ⚠️ WARN | `RawCullApp.swift` L16 | Move cleanup to `applicationWillTerminate(_:)` in `AppDelegate` for reliable shutdown. |

---

## 10. Memory Management & Memory Pressure

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| MEM-001 | `DiscardableThumbnail` correctly uses `NSDiscardableContent`; NSCache can discard items when under pressure. | ✅ PASS | `DiscardableThumbnail.swift` | Excellent. |
| MEM-002 | Memory pressure monitoring via `DispatchSourceMemoryPressure` responds to `.warning` (reduce to 60 %) and `.critical` (clear + 50 MB minimum). | ✅ PASS | `SharedMemoryCache.handleMemoryPressureEvent()` | Strong. |
| MEM-003 | `SharedMemoryCache.calculateConfig(from:)` converts `memoryCacheSizeMB` directly to bytes without capping against available physical memory. The settings slider range is 3000–20000 MB. On a Mac with 8 GB RAM, a user could configure a 20 GB cache limit — the OS will handle it, but `NSCache` will attempt to fill to that limit before evicting, causing unnecessary pressure. | ❌ FAIL | `SharedMemoryCache.calculateConfig(from:)` L96-110 | Cap `totalCostLimit` to e.g. 50–70 % of `ProcessInfo.processInfo.physicalMemory` at runtime. |
| MEM-004 | `GridThumbnailViewModel` holds an `[FileItem]` copy of `filteredFiles` — a potentially large duplicate array. This is acceptable for decoupling but should be documented. | ℹ️ INFO | `GridThumbnailViewModel.filteredFiles` | Note in code. |
| MEM-005 | Each `ScanAndCreateThumbnails` and `RequestThumbnail` instance creates its own `DiskCacheManager()`. Multiple instances therefore open/operate on the same disk cache directory independently. | ⚠️ WARN | `ScanAndCreateThumbnails.init`, `RequestThumbnail.init` | Inject `SharedMemoryCache.shared.diskCache` or use `DiskCacheManager` as a shared singleton. |

---

## 11. Security & Sandbox Entitlements

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| SEC-001 | App sandbox is enabled (`com.apple.security.app-sandbox = true`). | ✅ PASS | `RawCull.entitlements` | Required for Mac App Store. |
| SEC-002 | `com.apple.security.assets.pictures.read-only` is set — allows read-only access to the Pictures folder without user selection. | ✅ PASS | `RawCull.entitlements` | Appropriate for a photo culling app. |
| SEC-003 | `com.apple.security.files.user-selected.read-write` is set — allows read-write access to user-selected folders. This is needed for exporting JPGs back to the source directory. | ✅ PASS | `RawCull.entitlements` | Correct. |
| SEC-004 | `PrivacyInfo.xcprivacy` is present. | ✅ PASS | `RawCull/PrivacyInfo.xcprivacy` | Required for App Store submission. |
| SEC-005 | Security-scoped URL access in `ScanFiles` is correctly bracketed with `defer stop`. | ✅ PASS | `ScanFiles.swift` L27-28 | Correct. |
| SEC-006 | `ExecuteCopyFiles` stores and releases security-scoped URLs for source and destination. The `cleanup()` function should call `sourceAccessedURL?.stopAccessingSecurityScopedResource()` and same for destination. Verify this is implemented in the unread portion of `cleanup()`. | ⚠️ WARN | `ExecuteCopyFiles` | Confirm `cleanup()` releases both scoped resources; leaking a security scope can prevent other processes from accessing the folder. |
| SEC-007 | The `SIGNING_IDENTITY` in `Makefile` contains a hardcoded Team ID (`93M47F4H9T`). This is a personal Team ID, not a secret, but it should not be confused with a credential. | ℹ️ INFO | `Makefile` L7 | Acceptable; not a security risk. |
| SEC-008 | MD5 is used for disk cache key derivation (`Insecure.MD5`). This is explicitly for non-security purposes (cache keying). Using `CryptoKit.Insecure.MD5` and naming it `Insecure` signals the intent clearly. | ✅ PASS | `DiskCacheManager.cacheURL(for:)` | Correct use. |

---

## 12. Naming & API Design

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| NAME-001 | Actor names are clear and action-oriented: `ScanFiles`, `DiskCacheManager`, `ExtractAndSaveJPGs`. | ✅ PASS | `RawCull/Actors/` | Good. |
| NAME-002 | `ActorCreateOutputforView` uses mixed case without consistent capitalization (`forView` vs `ForView`). Minor but inconsistent with Swift naming conventions. | ⚠️ WARN | `RawCull/Actors/ActorCreateOutputforView.swift` | Rename to `ActorCreateOutputForView`. |
| NAME-003 | `asyncgetsettings()` in `SettingsViewModel` is lowercase — Swift convention is `asyncGetSettings()` or `getSettings()`. | ⚠️ WARN | `SettingsViewModel.asyncgetsettings` | Rename to camelCase. |
| NAME-004 | `WriteSavedFilesJSON` and `ReadSavedFilesJSON` are type names but read as function names. Swift convention for types is `SavedFilesJSONWriter` / `SavedFilesJSONReader`, or use static methods on a single `SavedFilesStorage` type. | ⚠️ WARN | `RawCull/Model/` | Consider refactoring to a single `SavedFilesStore` with `load()` and `save()` methods. |

---

## 13. Tooling Configuration

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| TOOL-001 | `.swiftlint.yml` is present. | ✅ PASS | `.swiftlint.yml` | Good. |
| TOOL-002 | `.swiftformat` is present. | ✅ PASS | `.swiftformat` | Good. |
| TOOL-003 | `.periphery.yml` is present for dead-code detection. | ✅ PASS | `.periphery.yml` | Good. |
| TOOL-004 | No CI workflow (GitHub Actions) is present in the repository. Linting, formatting and tests only run locally. | ⚠️ WARN | `.github/workflows/` (absent) | Add a GitHub Actions workflow to run SwiftLint, SwiftFormat check, and tests on every push/PR. |

---

## 14. Test Suite

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| TEST-001 | Three test files exist: `ThumbnailProviderTests`, `ThumbnailProviderAdvancedTests`, `ThumbnailProviderCustomMemoryTests`. Coverage focuses on the thumbnail/cache pipeline. | ✅ PASS | `RawCullTests/` | Good baseline. |
| TEST-002 | No tests for `ScanFiles`, `CullingModel`, `SettingsViewModel`, `ExecuteCopyFiles`, or the rsync pipeline. | ⚠️ WARN | `RawCullTests/` | Add unit tests for persistence, settings validation, and scan filtering. |
| TEST-003 | No UI tests or snapshot tests. | ℹ️ INFO | `RawCullTests/` | Acceptable for current scale; consider adding smoke tests for critical flows. |

---

## 15. Build & Distribution Pipeline

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| BUILD-001 | `Makefile` provides `build`, `debug`, `archive`, `sign-app`, `notarize`, `staple`, `prepare-dmg` targets — a complete CI-like local pipeline. | ✅ PASS | `Makefile` | Well-structured. |
| BUILD-002 | `archive` and `archive-debug` both depend on `clean` as a prerequisite — ensures no stale artifacts. | ✅ PASS | `Makefile` L16, L31 | Good. |
| BUILD-003 | `notarize` target hardcodes `--keychain-profile "RsyncUI"`. This couples the RawCull build to the RsyncUI keychain profile name, which is fragile if profiles differ across machines. | ⚠️ WARN | `Makefile` L64, L72 | Parameterise as `KEYCHAIN_PROFILE ?= RsyncUI` at the top of the Makefile. |
| BUILD-004 | `check` target hardcodes a specific notarisation submission UUID (`f62c4146-…`). This is a debugging leftover and should be removed or parameterised. | ⚠️ WARN | `Makefile` L109 | Remove or replace with `xcrun notarytool history`. |
| BUILD-005 | `prepare-dmg` uses `../create-dmg/create-dmg` — a relative path pointing outside the repo. If `create-dmg` is not checked out as a sibling directory, the build silently fails. | ⚠️ WARN | `Makefile` L88 | Document the dependency in `README.md`, or use `brew install create-dmg` and call `create-dmg` from `$PATH`. |

---

## 16. Summary & Priority Backlog

| Priority | ID | Title | Status |
|---|---|---|---|
| 🔴 P1 | CACHE-003 | No modification-date check on disk cache load — stale thumbnails served after source edits. | ❌ FAIL |
| 🔴 P1 | ERR-005 | `errorMessageOnly` is `#if DEBUG` — errors invisible in Release builds. | ❌ FAIL |
| 🔴 P1 | MEM-003 | Cache limit not capped against physical RAM — users can configure 20 GB limit on 8 GB Macs. | ❌ FAIL |
| 🔴 P1 | SCAN-003 | `ScanFiles` hard-codes `.arw` only despite `SupportedFileType` listing five formats. | ❌ FAIL |
| 🔴 P1 | ERR-009 | `SaveJPGImage` error path gated by `#if DEBUG`. | ❌ FAIL |
| 🟠 P2 | CONC-007 | `.task(id:)` wraps inner unstructured `Task` — previous scan not fully cancelled on rapid source change. | ⚠️ WARN |
| 🟠 P2 | CONC-013 | `viewModel.scanning.toggle()` in view conflicts with `handleSourceChange` owning `scanning` state. | ⚠️ WARN |
| 🟠 P2 | CACHE-010 | `ensureReady()` double-configure race — use `setupTask` pattern. | ⚠️ WARN |
| 🟠 P2 | CACHE-014 | `updateCacheDisk` logs "found in RAM Cache" — copy-paste bug obscures diagnostics. | ⚠️ WARN |
| 🟠 P2 | ERR-006 | Memory pressure handler logs at debug level — critical events invisible in Release. | ⚠️ WARN |
| 🟠 P2 | UI-010 | `performCleanupTask()` does nothing — cache and settings not flushed on quit. | ⚠️ WARN |
| 🟠 P2 | UI-011 | `applicationWillTerminate` is empty stub — cleanup may not run on forced termination. | ⚠️ WARN |
| 🟠 P2 | PERS-002 | `WriteSavedFilesJSON` called synchronously on main actor — may block UI for large catalogs. | ⚠️ WARN |
| 🟠 P2 | MEM-005 | Multiple `DiskCacheManager` instances for same directory — should be shared singleton. | ⚠️ WARN |
| 🟡 P3 | CONC-008 | `ExtractAndSaveJPGs` inner `Task` may stall actor for large loops. | ⚠️ WARN |
| 🟡 P3 | CONC-009 | `SettingsViewModel` init race — defaults returned if accessed before load completes. | ⚠️ WARN |
| 🟡 P3 | CONC-012 | `ScanFiles` actor created fresh on every source change — wasteful allocation. | ⚠️ WARN |
| 🟡 P3 | CACHE-005 | No disk cache size cap — disk can grow unbounded without manual pruning. | ⚠️ WARN |
| 🟡 P3 | SCAN-005 | EXIF extraction failure silent — no logging. | ⚠️ WARN |
| 🟡 P3 | SCAN-007 | `DiscoverFiles` implicit security-scope dependency undocumented. | ⚠️ WARN |
| 🟡 P3 | RSYNC-006 | rsync failure not surfaced to user — no alert on copy error. | ⚠️ WARN |
| 🟡 P3 | UI-004 | `FileContentView` uses `AnyView` — replace with generic `@ViewBuilder` parameter. | ⚠️ WARN |
| 🟡 P3 | UI-009 | Memory warning flash opacity not reset after warning clears. | ⚠️ WARN |
| 🟡 P3 | TOOL-004 | No GitHub Actions CI — linting and tests are local-only. | ⚠️ WARN |
| 🟡 P3 | BUILD-003 | Hardcoded `--keychain-profile "RsyncUI"` in Makefile. | ⚠️ WARN |
| 🟡 P3 | BUILD-004 | Hardcoded notarisation UUID in `check` target. | ⚠️ WARN |
| 🟡 P3 | BUILD-005 | `create-dmg` path relative outside repo — fragile dependency. | ⚠️ WARN |
| ~~🔴 P1~~ | ~~ARCH-008~~ | ~~`abort()` was a no-op.~~ | ✅ FIXED |
| ~~🔴 P1~~ | ~~PERS-003~~ | ~~`CullingModel` data race on `savedFiles`.~~ | ✅ FIXED |
| ~~🔴 P1~~ | ~~ERR-003~~ | ~~`DiskCacheManager.save()` silently drops write errors.~~ | ✅ FIXED |
| ~~🟠 P2~~ | ~~ARCH-004~~ | ~~`CullingModel` not `@MainActor`.~~ | ✅ FIXED |
| ~~🟠 P2~~ | ~~SCAN-004~~ | ~~EXIF extraction serially blocked actor.~~ | ✅ FIXED |
| ~~🟠 P2~~ | ~~RSYNC-003~~ | ~~`ArgumentsSynchronize` filter-file write race.~~ | ✅ FIXED |
| ~~🟡 P3~~ | ~~UI-003~~ | ~~`.onChange` task not cancelled on rapid source changes.~~ | ✅ FIXED (partially — see CONC-007) |