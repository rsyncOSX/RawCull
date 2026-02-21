# Static Analysis Report — RawCull

> **Report date:** 2026-02-21
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

Critical Fail (❌) summaries, presented in chapter 16, are periodically updated as new updates are implemented.

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

### Directory tree (as of 2026-02-21)

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
| LAYOUT-002 | `SupportedFileType` and `WindowIdentifier` enums live in `RawCullApp.swift` rather than their own files, mixing app-entry concerns with domain types. | ⚠️ WARN |
| LAYOUT-003 | `ThumbnailError` is defined inside `RequestThumbnail.swift` (indicated by comment header `ThumbnailError.swift`). It is used by `DiskCacheManager` and `SonyThumbnailExtractor` — cross-file type dependency hidden inside a single file. | ⚠️ WARN |
| LAYOUT-004 | No `Package.swift` / Swift Package Manager manifest. The project is pure Xcode. Acceptable for a macOS-only app, but limits library extraction later. | ℹ️ INFO |

---

## 2. Architecture & MVVM Boundaries

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| ARCH-001 | MVVM separation is clear. Views are thin; ViewModels own observable state; background work is isolated in actors. | ✅ PASS | `RawCullViewModel`, `RawCull/Actors/` | Overall structure is consistent. |
| ARCH-002 | `RawCullViewModel` is `@Observable @MainActor`. All UI-mutating state (`files`, `progress`, `scanning`, …) is main-actor-bound. | ✅ PASS | `RawCull/Model/ViewModels/RawCullViewModel.swift` | Correct isolation. |
| ARCH-003 | `ExecuteCopyFiles` is `@Observable @MainActor` and correctly confines its UI-facing callbacks to the main actor. | ✅ PASS | `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift` | Good. |
| ARCH-004 | `CullingModel` is `@Observable` but **not** `@MainActor`. It is mutated synchronously from main-actor context (toggle/reset) without explicit actor hopping. Mutations are safe only because they happen to be called from views/viewmodels that are already on the main actor, but this is implicit, not enforced. | ⚠️ WARN | `RawCull/Model/ViewModels/CullingModel.swift` | Add `@MainActor` annotation or document the threading contract. |
| ARCH-005 | `GridThumbnailViewModel` is `@Observable @MainActor`. Holds references to `RawCullViewModel` and `CullingModel` — creates an optional cross-ViewModel reference that must be set before use. No guard against use-before-set (nil-crash path). | ⚠️ WARN | `RawCull/Model/ViewModels/GridThumbnailViewModel.swift` | Consider a precondition or Result type. |
| ARCH-006 | `SettingsViewModel.shared` is a `@MainActor` singleton accessed via `await SettingsViewModel.shared.asyncgetsettings()` from non-main-actor code. This is correct but means actors must always `await` to read settings, adding latency. | ℹ️ INFO | `RawCull/Model/ViewModels/SettingsViewModel.swift` | Not a defect; note for future optimisation. |
| ARCH-007 | `FileHandlers` is injected into actors via `setFileHandlers(_:)`. This is a good dependency-injection pattern and aids testability. | ✅ PASS | `ScanAndCreateThumbnails`, `ExtractAndSaveJPGs` | Keep consistent. |
| ARCH-008 | `abort()` in `RawCullViewModel` has comment `// Implementation deferred`. The UI calls this via `MenuCommands`. The abort button is therefore a no-op at runtime. | ❌ FAIL | `RawCull/Model/ViewModels/RawCullViewModel.swift` L147 | Implement or disable the menu item. |

---

## 3. Swift Concurrency Model

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| CONC-001 | Heavy I/O and CPU work (scanning, thumbnail extraction, disk cache) isolated to actors off the main thread. | ✅ PASS | `RawCull/Actors/` | Good isolation. |
| CONC-002 | `DiscoverFiles.discoverFiles` uses `Task.detached { [self] in … }` and reads `self.supported` inside the detached closure. Because `supported` is `nonisolated let`, this compiles without warning but technically crosses actor isolation for a constant. In strict concurrency it can trigger warnings. | ⚠️ WARN | `RawCull/Actors/DiscoverFiles.swift` L15-28 | Copy `supported` to a local `let` before the detached block for clarity. |
| CONC-003 | `ScanAndCreateThumbnails.preloadCatalog` and `ExtractAndSaveJPGs.extractAndSaveAlljpgs` both check `Task.isCancelled` at the start of each iteration and call `group.cancelAll()`. | ✅ PASS | `ScanAndCreateThumbnails.swift`, `ExtractAndSaveJPGs.swift` | Correct cancellation propagation. |
| CONC-004 | `DiskCacheManager.load` and `.save` use `Task.detached` with explicit priority, capturing only value types (`fileURL`, `cgImage`), preventing the actor from being retained. | ✅ PASS | `RawCull/Actors/DiskCacheManager.swift` | Good pattern. |
| CONC-005 | `SharedMemoryCache.memoryCache` (`NSCache`) is declared `nonisolated(unsafe) let`. This is correct because `NSCache` is internally thread-safe. The code comment explains the rationale. | ✅ PASS | `RawCull/Actors/SharedMemoryCache.swift` L35 | Well-documented. |
| CONC-006 | `CacheDelegate._evictionCount` uses `nonisolated(unsafe) var` protected by an `NSLock`. This is safe but low-level. | ✅ PASS | `RawCull/Model/Cache/CacheDelegate.swift` | Acceptable; consider `OSAllocatedUnfairLock` (already used in `DiscardableThumbnail`) for consistency. |
| CONC-007 | `RawCullView` spawns `Task(priority: .background)` directly inside `.onChange` handlers for source/sort/search changes. These tasks hop back to `@MainActor` viewModel methods. No handle is retained to cancel them if the view disappears quickly. | ⚠️ WARN | `RawCull/Views/RawCullView/RawCullView.swift` L115-139 | Store the `Task` and cancel it in `.onDisappear`, or use `.task(id:)` modifiers (which auto-cancel). |
| CONC-008 | `ExtractAndSaveJPGs.extractAndSaveAlljpgs` wraps work in an unstructured `Task { … }` stored as `extractJPEGSTask`. This is correct but it means the inner task inherits the actor's isolation and all `self.` mutations within run on the actor. Verify that large loops in this task do not stall the actor. | ⚠️ WARN | `RawCull/Actors/ExtractAndSaveJPGs.swift` L33 | Consider structured `withTaskGroup` directly on the actor function signature instead. |
| CONC-009 | `SettingsViewModel.loadSettings()` is called from `init()` inside a `Task { await loadSettings() }`. If `SettingsViewModel.shared` is accessed before that task completes, default values will be returned. There is no synchronisation guard against this race. | ⚠️ WARN | `RawCull/Model/ViewModels/SettingsViewModel.swift` L22-24 | Use a `setupTask` pattern (already used in `SharedMemoryCache`) to serialise first-access. |
| CONC-010 | `@preconcurrency import AppKit` and `@preconcurrency import ImageIO` are used in `EmbeddedPreviewExtractor.swift` and `SaveJPGImage.swift`. This suppresses warnings without fully adopting strict sendability for those types. | ⚠️ WARN | `RawCull/Actors/SaveJPGImage.swift`, `RawCull/Enum/EmbeddedPreviewExtractor.swift` | Track and remove `@preconcurrency` when Apple adopts strict concurrency annotations for those frameworks. |
| CONC-011 | `SonyThumbnailExtractor.extractSonyThumbnail` manually dispatches to `DispatchQueue.global` via `withCheckedThrowingContinuation` to avoid blocking the calling actor. This is correct but can be simplified with `async` on the extraction work directly (requires macOS 15+ `@concurrent` or explicit nonisolated). | ℹ️ INFO | `RawCull/Enum/SonyThumbnailExtractor.swift` L27-38 | Works correctly; note for future simplification. |

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
| CACHE-011 | `DiskCacheManager.save(_:for:)` uses `try? Self.writeImageToDisk(...)` inside a detached task. Any write failure (disk full, permissions) is silently dropped. | ❌ FAIL | `DiskCacheManager.swift` L53 | Catch and log the error: `do { try … } catch { Logger.process.warning(…) }`. |
| CACHE-012 | Thumbnail JPEG quality for disk cache is hard-coded at `0.7` in `DiskCacheManager.writeImageToDisk`. No setting exposes this to users. | ℹ️ INFO | `DiskCacheManager.swift` L71 | Acceptable default; consider adding to settings if quality complaints arise. |
| CACHE-013 | `SonyThumbnailExtractor` and `EmbeddedPreviewExtractor` are both used, serving different purposes (preview vs. full-size extraction). The naming could imply they are Sony-specific. `EmbeddedPreviewExtractor` is the generic path; both correctly use `CGImageSourceCreateThumbnailAtIndex`. | ℹ️ INFO | `RawCull/Enum/` | Consider renaming `SonyThumbnailExtractor` → `RAWThumbnailExtractor` for clarity. |

---

## 5. File Scanning & EXIF Metadata

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| SCAN-001 | `ScanFiles.scanFiles` correctly calls `startAccessingSecurityScopedResource()` and wraps the scope in a `defer` statement. | ✅ PASS | `RawCull/Actors/ScanFiles.swift` L22-24 | Correct sandbox handling. |
| SCAN-002 | Directory enumeration uses `.skipsHiddenFiles`. | ✅ PASS | `ScanFiles.scanFiles` L36 | Good. |
| SCAN-003 | File filtering is limited to `.arw` extension only, despite `SupportedFileType` listing `arw`, `tiff`, `tif`, `jpeg`, `jpg`. `ScanFiles` hard-codes only ARW. | ❌ FAIL | `ScanFiles.swift` L42 | Either remove unused enum cases or use `SupportedFileType.allCases.map { $0.rawValue }` for the extension filter to keep declaration and behaviour in sync. |
| SCAN-004 | `extractExifData` performs synchronous `CGImageSourceCreateWithURL` on the actor's thread for every scanned file. For large catalogs (hundreds of ARW files) this will serially block the actor during scan. | ⚠️ WARN | `ScanFiles.scanFiles` L46, `extractExifData` L78 | Move EXIF extraction to a `@concurrent nonisolated` function or a detached task so it runs in parallel. |
| SCAN-005 | EXIF extraction failure returns `nil` without any logging. | ⚠️ WARN | `ScanFiles.extractExifData` L78-86 | Add `Logger.process.debug("extractExifData: no EXIF at \(url.lastPathComponent)")` for diagnostics. |
| SCAN-006 | `ScanFiles.sortFiles` is `@concurrent nonisolated` — it correctly runs off-actor, which is good for performance on large catalogs. | ✅ PASS | `ScanFiles.sortFiles` L63-72 | Good. |
| SCAN-007 | `DiscoverFiles.discoverFiles` does not call `startAccessingSecurityScopedResource()` even though it operates on user-selected URLs. It is always called with catalogs already opened by `ScanFiles` or `ScanAndCreateThumbnails`. This indirect dependency is not documented. | ⚠️ WARN | `RawCull/Actors/DiscoverFiles.swift` | Add a comment or assertion clarifying that callers must hold the security-scoped resource. |

---

## 6. Persistence Layer (JSON / Culling)

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| PERS-001 | `CullingModel` persists tagged/rated file records to JSON via `WriteSavedFilesJSON` and reads via `ReadSavedFilesJSON`. This is a straightforward approach for an app of this scale. | ✅ PASS | `CullingModel.swift` | Simple and appropriate. |
| PERS-002 | `WriteSavedFilesJSON` is called synchronously on the calling thread inside `CullingModel.toggleSelectionSavedFiles`. For large `savedFiles` arrays this could stall the main thread. | ⚠️ WARN | `CullingModel.toggleSelectionSavedFiles` | Dispatch write to a background task. |
| PERS-003 | `CullingModel` is not `@MainActor`, but its `savedFiles` array is mutated from main-actor view code and read from background contexts (e.g., `extractTaggedfilenames` called from `ExecuteCopyFiles`). No explicit thread-safety mechanism protects `savedFiles`. | ❌ FAIL | `CullingModel.swift`, `RawCullViewModel.extractTaggedfilenames` | Mark `CullingModel` as `@MainActor` or convert to an `actor`. |
| PERS-004 | `SettingsViewModel.loadSettings()` and `saveSettings()` both call `FileManager.default.createDirectory` on the calling context. `loadSettings` is called from `init` inside a `Task`, so directory creation may race with first access. | ⚠️ WARN | `SettingsViewModel.swift` | Ensure directory creation is serialised (the `Task` pattern already helps, but `saveSettings` can be called independently). |
| PERS-005 | `SettingsViewModel.validateSettings()` exists but its contents were not visible in the analysed excerpt. Confirm it clamps all values to sane ranges before saving. | ℹ️ INFO | `SettingsViewModel.saveSettings` | Verify completeness. |

---

## 7. rsync Integration (Copy Pipeline)

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| RSYNC-001 | `ExecuteCopyFiles` is `@Observable @MainActor` and holds `weak var sidebarRawCullViewModel: RawCullViewModel?`. Using `weak` prevents retain cycles. | ✅ PASS | `ExecuteCopyFiles.swift` L20 | Correct. |
| RSYNC-002 | Security-scoped resources for source and destination folders are accessed via bookmark keys (`sourceBookmark`, `destBookmark`) with a path fallback. The lifetime is managed with `sourceAccessedURL`/`destAccessedURL` stored on the object. | ✅ PASS | `ExecuteCopyFiles.startcopyfiles` | Correct pattern. |
| RSYNC-003 | `ArgumentsSynchronize` builds the rsync argument list. The `--include-from=` parameter path is a Documents-directory file (`copyfilelist.txt`). This file is written synchronously on the main actor immediately before the process starts, which is fine for single invocations but could race if two copy operations were triggered rapidly. | ⚠️ WARN | `ExecuteCopyFiles.startcopyfiles` L52 | Enforce single-operation-at-a-time in the UI (already done via `executionManager` state) and assert exclusivity. |
| RSYNC-004 | The filter file is written to `Documents/copyfilelist.txt` — a fixed path. If the app is running multiple simultaneous copy operations (not currently possible, but worth noting), they would collide on this file. | ℹ️ INFO | `ExecuteCopyFiles.savePath` | Document that only one copy operation is supported at a time. |
| RSYNC-005 | `RsyncProcessStreaming` is used for streaming output. Progress updates call back via `onProgressUpdate` and `onCompletion` closures, which dispatch to `@MainActor`. | ✅ PASS | `ExecuteCopyFiles.startcopyfiles` | Good streaming pattern. |
| RSYNC-006 | Failure path of `process.executeProcess()` calls `Logger.process.errorMessageOnly` and then `Task { @MainActor in self.cleanup() }`. The error is logged but **not surfaced to the user** (no alert or completion callback with error). | ⚠️ WARN | `ExecuteCopyFiles.startcopyfiles` L120-125 | Call `onCompletion` with an error result so the UI can inform the user. |

---

## 8. Error Handling & Logging

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| ERR-001 | `ThumbnailError` is a typed `LocalizedError` with meaningful `errorDescription` values for `invalidSource`, `generationFailed`, and `contextCreationFailed`. | ✅ PASS | `RequestThumbnail.swift` | Good. |
| ERR-002 | `DiskCacheManager.init()` now uses `do { try … } catch { Logger.process.warning(…) }` for directory creation. | ✅ PASS | `DiskCacheManager.swift` L12-18 | Previously flagged; now fixed. |
| ERR-003 | `DiskCacheManager.save()` uses `try? Self.writeImageToDisk(...)` — any write failure is silently dropped. | ❌ FAIL | `DiskCacheManager.swift` L53 | Wrap in `do/catch` and log. |
| ERR-004 | `SettingsViewModel.saveSettings()` and `loadSettings()` both use `do/catch` with `Logger.process.errorMessageOnly`. | ✅ PASS | `SettingsViewModel.swift` | Good. |
| ERR-005 | `Logger.process.errorMessageOnly` and `debugMessageOnly` are `#if DEBUG` gated — errors are **not logged in Release builds**. This means production users and crash reporters cannot see error messages from these calls. | ❌ FAIL | `extension+Thread+Logger.swift` L32-34 | `errorMessageOnly` should use `os_log` at `.error` level unconditionally. Only `debugMessageOnly` and `debugThreadOnly` should be `#if DEBUG` gated. |
| ERR-006 | Memory pressure handler logs only at `debug` level (`Logger.process.debugMessageOnly`). Critical pressure events (cache cleared) should be logged at `.warning` or `.error` unconditionally. | ⚠️ WARN | `SharedMemoryCache.logMemoryPressure` | Use `Logger.process.warning(…)` for `.warning` and `.critical` events. |
| ERR-007 | `ScanFiles.scanFiles` logs scan errors at `.warning`. | ✅ PASS | `ScanFiles.swift` L54 | Good. |
| ERR-008 | `EmbeddedPreviewExtractor` logs at `.warning` for missing image source and missing JPEG, and at `.info` for normal decode paths. Appropriate levels. | ✅ PASS | `EmbeddedPreviewExtractor.swift` | Good. |
| ERR-009 | `SaveJPGImage.save` logs both success and failure via `Logger.process.info` and `Logger.process.error`. However, `.error` calls are guarded by `#if DEBUG` via `errorMessageOnly`. Same issue as ERR-005. | ❌ FAIL | `SaveJPGImage.swift` L35-42 | Use unconditional `Logger.process.error(…)` for the failure path. |

---

## 9. SwiftUI View Layer

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| UI-001 | Root navigation uses `NavigationSplitView` with sidebar / content / detail columns — idiomatic for macOS. | ✅ PASS | `RawCullView.swift` | Good. |
| UI-002 | `SettingsView` and all settings tabs receive `SettingsViewModel` via `@Environment`. | ✅ PASS | `SettingsView.swift` L10 | Good. |
| UI-003 | `RawCullViewModel.handleSourceChange` is called from a `.onChange(of:)` modifier via `Task(priority: .background)`. No handle is retained; if the selected source changes again quickly, both tasks will run concurrently and the second scan may complete before the first, leaving stale state. | ❌ FAIL | `RawCullView.swift` L115-121 | Switch to `.task(id: viewModel.selectedSource)` which automatically cancels the previous task when the ID changes. |
| UI-004 | `FileContentView` accepts `AnyView` as the `filetableview` parameter, bypassing SwiftUI's type-erasure optimisations. | ⚠️ WARN | `RawCull/Views/FileViews/FileContentView.swift` | Replace with a generic `Content: View` parameter and `@ViewBuilder`. |
| UI-005 | `RawCullAlertView` is a caseless enum used as a namespace for a static factory method. This is an acceptable Swift pattern. | ✅ PASS | `RawCullAlertView.swift` | Fine. |
| UI-006 | `CacheStatisticsView` polls cache stats via an `AsyncStream` timer firing every 5 seconds. The stream is properly cancelled when the task is cancelled via structured concurrency. | ✅ PASS | `CacheStatisticsView.swift` | Good pattern. |
| UI-007 | `MemoryTab` polls memory stats via an `AsyncStream` timer every 1 second. `try? await Task.sleep(nanoseconds:)` inside the stream continuation — a `Task.isCancelled` check exists. However, if `updateMemoryStats()` is synchronous and expensive, it will run on the continuation's thread. | ⚠️ WARN | `MemoryTab.swift` | Verify `updateMemoryStats()` is cheap or dispatch to a background context. |
| UI-008 | `ConditionalGlassButton` contains an `if #available(macOS 26.0, *)` branch. macOS 26 is not yet released (as of 2026-02-21). This is forward-looking code for a beta OS. | ℹ️ INFO | `ButtonStyles.swift` | Fine for development; ensure the fallback branch is fully tested on current macOS. |
| UI-009 | `RawCullView` subscribes to `viewModel.memorypressurewarning` via `.onChange` and starts a `withAnimation(.repeatForever)`. This animation runs indefinitely until dismissed — correct behaviour, but the animation value is never reset to `0.3` after the warning clears. | ⚠️ WARN | `RawCullView.swift` startMemoryWarningFlash() | Reset `memoryWarningOpacity` to `0.3` when `memorypressurewarning` returns to `false`. |
| UI-010 | `RawCullApp.performCleanupTask()` logs a debug message but performs no actual cleanup (no cache flush, no settings save). Given that `SharedMemoryCache` and `SettingsViewModel` hold in-flight state, shutdown is clean only by virtue of OS reclamation. | ⚠️ WARN | `RawCullApp.swift` L97-99 | Consider calling `await SharedMemoryCache.shared.stopMemoryPressureMonitoring()` and `await SettingsViewModel.shared.saveSettings()` on termination. |

---

## 10. Memory Management & Memory Pressure

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| MEM-001 | `DiscardableThumbnail` correctly uses `NSDiscardableContent`; NSCache can discard items when under pressure. | ✅ PASS | `DiscardableThumbnail.swift` | Excellent. |
| MEM-002 | Memory pressure monitoring via `DispatchSourceMemoryPressure` responds to `.warning` (reduce to 60 %) and `.critical` (clear + 50 MB minimum). | ✅ PASS | `SharedMemoryCache.handleMemoryPressureEvent()` | Strong. |
| MEM-003 | `SharedMemoryCache` default `CacheConfig.production` sets 500 MB total cost limit and 1000 count limit. However, the `memoryCacheSizeMB` setting in `SettingsViewModel` defaults to 5000 MB, and the slider range is 3000–20000 MB. The `calculateConfig(from:)` in `SharedMemoryCache` must reconcile these. If it uses the settings value directly, users could accidentally set a 20 GB memory limit. | ❌ FAIL | `SettingsViewModel.memoryCacheSizeMB` default = 5000, `CacheConfig.production.totalCostLimit` = 500 MB | Validate and cap the effective cache limit against available physical memory at runtime. |
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
| SEC-005 | Security-scoped URL access in `ScanFiles` is correctly bracketed with `defer stop`. | ✅ PASS | `ScanFiles.swift` L22-24 | Correct. |
| SEC-006 | `ExecuteCopyFiles` stores and releases security-scoped URLs for source and destination. The `cleanup()` function should call `sourceAccessedURL?.stopAccessingSecurityScopedResource()` and same for destination. Verify this is implemented in the unread portion of `cleanup()`. | ⚠️ WARN | `ExecuteCopyFiles` | Confirm `cleanup()` releases both scoped resources; leaking a security scope can prevent other processes from accessing the folder. |
| SEC-007 | The `SIGNING_IDENTITY` in `Makefile` contains a hardcoded Team ID (`93M47F4H9T`). This is a personal Team ID, not a secret, but it should not be confused with a credential. | ℹ️ INFO | `Makefile` L7 | Acceptable; not a security risk. |
| SEC-008 | MD5 is used for disk cache key derivation (`Insecure.MD5`). This is explicitly for non-security purposes (cache keying). Using `CryptoKit.Insecure.MD5` and naming it `Insecure` signals the intent clearly. | ✅ PASS | `DiskCacheManager.cacheURL(for:)` | Correct use. |

---

## 12. Naming & API Design

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| NAME-001 | Most type names follow `UpperCamelCase`: `SonyThumbnailExtractor`, `EmbeddedPreviewExtractor`, `DiscardableThumbnail`, `CacheDelegate`, `FileItem`, `ARWSourceCatalog`. | ✅ PASS | Throughout | Good. |
| NAME-002 | Several property names use abbreviated or non-idiomatic casing: `creatingthumbnails` (should be `creatingThumbnails`), `issorting` (should be `isSorting`), `showcopytask` (should be `showCopyTask`), `remotedatanumbers` (should be `remoteDataNumbers`). | ⚠️ WARN | `RawCullViewModel.swift` | Run SwiftLint's `identifier_name` rule; fix incrementally. |
| NAME-003 | `asyncgetsettings()` (on `SettingsViewModel`) does not follow Swift's `async` naming convention. Async functions should not have `async` in their name — the `async` keyword in the call site makes it obvious. | ⚠️ WARN | `SettingsViewModel.asyncgetsettings()` | Rename to `getSettings()` or simply expose a computed `var settings: SavedSettings` if the data can be cached. |
| NAME-004 | `ActorCreateOutputforView` is a poorly-named actor. It creates `[RsyncOutputData]` from strings. Consider `RsyncOutputFormatter` or `OutputFormatter`. The `forView` suffix implies UI coupling which is not ideal for an actor. | ⚠️ WARN | `ActorCreateOutputforView.swift` | Rename for clarity. |
| NAME-005 | `upadateCacheDisk()` (typo: `upadate`) on `SharedMemoryCache`. | ❌ FAIL | `SharedMemoryCache` | Rename to `updateCacheDisk()`. |
| NAME-006 | `SupportedFileType.arw` produces `.rawValue == "arw"` which is used for extension comparison. The enum has `jpeg`/`jpg`/`tiff`/`tif` but only `arw` is used in scanning. Unused enum cases should be removed or scanning logic extended. | ⚠️ WARN | `RawCullApp.swift` L109-123, `ScanFiles.swift` L42 | Aligns with SCAN-003. |
| NAME-007 | `WriteJSONFilesPersistance` style names (if present) follow the spelling `Persistance` (incorrect; should be `Persistence`). | ⚠️ WARN | Verify in `WriteSavedFilesJSON` / `ReadSavedFilesJSON` | Fix spelling if present. |

---

## 13. Tooling Configuration

### SwiftLint (`.swiftlint.yml`)

Opted-in rules include `force_unwrapping`, `force_cast`, `unused_declaration`, `weak_delegate`, `sorted_imports`, `yoda_condition`, `implicit_return`, `multiline_arguments`, and more. Limits: `line_length: 135`, `type_body_length: 320`.

| ID | Check | Status | Notes |
|---|---|---|---|
| TOOL-001 | `force_unwrapping` and `force_cast` are enabled — good safety net. | ✅ PASS | |
| TOOL-002 | `unused_declaration` is enabled. Combined with Periphery, this provides two layers of dead-code detection. | ✅ PASS | |
| TOOL-003 | `discouraged_optional_boolean` is commented out. `Bool?` is used in some places. Consider enabling for stricter correctness. | ⚠️ WARN | |
| TOOL-004 | No `disabled_rules` section — all default rules remain active. | ✅ PASS | |
| TOOL-005 | SwiftLint is not run as part of the `Makefile` build pipeline. It requires a manual invocation. | ⚠️ WARN | Add `swiftlint` target to `Makefile`. |

### SwiftFormat (`.swiftformat`)

Single rule: `--disable redundantSelf`.

| ID | Check | Status | Notes |
|---|---|---|---|
| TOOL-006 | Disabling `redundantSelf` is intentional — code uses explicit `self.` in closures for clarity. This is a valid style preference. | ✅ PASS | |
| TOOL-007 | No other SwiftFormat rules configured. The formatter will apply all defaults except `redundantSelf`. This could cause unexpected reformatting on first run. | ⚠️ WARN | Consider an explicit `--swiftversion 6.0` flag and document any other rule overrides. |

### Periphery (`.periphery.yml`)

```yaml
project: RawCull.xcodeproj
retain_objc_accessible: true
retain_public: true
schemes:
- RawCull
```

| ID | Check | Status | Notes |
|---|---|---|---|
| TOOL-008 | `retain_public: true` means public declarations are not reported as unused. Since this is a single-target app (not a framework), all types could be `internal`. Consider setting `retain_public: false` to catch unused public declarations. | ⚠️ WARN | |
| TOOL-009 | Periphery is not run in the `Makefile`. Add a `periphery scan` target for CI integration. | ⚠️ WARN | |

### CI / GitHub Actions

| ID | Check | Status | Notes |
|---|---|---|---|
| TOOL-010 | No GitHub Actions workflow is present in the repository. All quality gates (lint, format, test) must be run manually. | ⚠️ WARN | Add a `.github/workflows/ci.yml` that runs `swiftlint`, `swiftformat --lint`, and `xcodebuild test`. |

---

## 14. Test Suite

### Files

| File | Suite | Test count (approx.) |
|---|---|---|
| `ThumbnailProviderTests.swift` | `RequestThumbnailTests` | ~10 |
| `ThumbnailProviderAdvancedTests.swift` | Advanced Memory, Stress, Edge Case, Config, Discardable, Isolation | ~20 |
| `ThumbnailProviderCustomMemoryTests.swift` | Custom Memory Limits, Memory Pressure, Config Comparison, Eviction Monitoring, Realistic Workloads | ~15 |

All tests use the **Swift Testing** framework (`import Testing`, `@Suite`, `@Test`, `#expect`).

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| TEST-001 | Uses Swift Testing framework consistently. | ✅ PASS | All test files | Modern approach. |
| TEST-002 | Tests cover `RequestThumbnail` initialisation, cache statistics, memory limits, concurrent access, edge cases, and discardable content. | ✅ PASS | All three test files | Good coverage of the caching layer. |
| TEST-003 | Several tests contain `#expect(true)` with a comment like `// Placeholder — full implementation requires cache introspection`. These are no-op tests that always pass and provide no coverage value. | ❌ FAIL | `ThumbnailProviderTests.swift` L103, L109; `ThumbnailProviderCustomMemoryTests.swift` L74 | Replace with real assertions or mark with `@Test(.disabled(…))` and link a tracking issue. |
| TEST-004 | Tests for `ScanFiles`, `CullingModel`, `SettingsViewModel`, `ExecuteCopyFiles`, and `DiskCacheManager` are entirely absent. The test suite covers only the thumbnail/cache layer. | ❌ FAIL | — | Add unit tests for: `ScanFiles.scanFiles` (mock filesystem), `CullingModel.toggleSelectionSavedFiles`, `SettingsViewModel.loadSettings`/`saveSettings`, `DiskCacheManager.cacheURL`. |
| TEST-005 | `createTestImage()` is a free function (not in a test helper type) and is duplicated-by-usage across all three test files. | ⚠️ WARN | All test files | Move to a shared `TestHelpers.swift` file in `RawCullTests`. |
| TEST-006 | No integration test exercises the full thumbnail pipeline (scan → create thumbnail → cache → retrieve). | ⚠️ WARN | — | Add an integration test using a small set of real or synthetic ARW-shaped files. |
| TEST-007 | Some stress tests (`rapidSequentialOperations` with 100 iterations, `highConcurrencyStatistics` with 50 tasks) only observe `hitRate >= 0` — trivially true. They are useful for detecting crashes/hangs but not for correctness. | ⚠️ WARN | `ThumbnailProviderAdvancedTests.swift` | Add behaviour assertions (e.g., after 50 puts, count should be ≤ countLimit). |
| TEST-008 | `@MainActor` is applied to several test suites (`RequestThumbnailStressTests`, `RequestThumbnailEdgeCaseTests`). This is correct when testing `@MainActor`-isolated types but should be removed from suites that don't require it, to avoid unnecessarily serialising tests. | ⚠️ WARN | `ThumbnailProviderAdvancedTests.swift` | Review per-suite isolation needs. |

---

## 15. Build & Distribution Pipeline

| ID | Check | Status | Evidence | Notes |
|---|---|---|---|---|
| BUILD-001 | `Makefile` provides `build` (release), `debug`, `sign-app`, `notarize`, `staple`, `prepare-dmg`, and `clean` targets — a complete manual distribution pipeline. | ✅ PASS | `Makefile` | Well-structured. |
| BUILD-002 | xcodebuild destination is hard-coded to `platform=OS X,arch=x86_64`. This excludes Apple Silicon (arm64) native builds. | ❌ FAIL | `Makefile` L21, L36 | Use `platform=macOS` (no arch) or `platform=OS X,arch=arm64` / universal via `ARCHS="x86_64 arm64"`. |
| BUILD-003 | `VERSION = 1.0.6` is hard-coded in the `Makefile` and must be manually bumped. It is not read from the Xcode project's `MARKETING_VERSION`. | ⚠️ WARN | `Makefile` L3 | Read version from `agvtool what-marketing-version -terse` or `xcrun agvtool next-version -all` to keep a single source of truth. |
| BUILD-004 | `check` target contains a hard-coded notarytool submission ID (`f62c4146-…`). This is a debug leftover. | ⚠️ WARN | `Makefile` L109 | Remove or replace with a dynamic lookup. |
| BUILD-005 | The `notarize` target uses `--keychain-profile "RsyncUI"`. This is a personal developer keychain profile name. The `Makefile` is committed to the repository — any contributor cloning the repo would need to create the same profile. | ℹ️ INFO | `Makefile` L64 | Document in README or `Makefile` comments that contributors need to configure this keychain profile. |
| BUILD-006 | `create-dmg` is referenced as `../create-dmg/create-dmg` — a path relative to the repo's parent directory. This is a fragile external dependency. | ⚠️ WARN | `Makefile` L88 | Add `create-dmg` as a git submodule, Homebrew dependency, or download step in the `Makefile`. |

---

## 16. Summary & Priority Backlog

### ❌ Critical FAIL items (fix immediately)

| Priority | ID | Issue |
|---|---|---|
| P1 | ARCH-008 | `abort()` is a no-op — user can trigger it from the menu with no effect. |
| P1 | ~~SCAN-003~~ | `ScanFiles` only scans `.arw` files, inconsistent with `SupportedFileType` enum. |
| P1 | ~~PERS-003~~ | `CullingModel` is not thread-safe — `savedFiles` is mutated without actor/main-actor protection. Added @MainActor to class|
| P1 | ~~UI-003~~| `.onChange` for source selection uses unstructured `Task` — rapid changes can produce stale UI state. |
| P1 | ERR-005 | `errorMessageOnly` is `#if DEBUG` only — errors are invisible in Release builds. |
| P1 | ERR-009 | `SaveJPGImage` failure path uses `errorMessageOnly` — silent in Release. |
| P1 | CACHE-003 | No disk cache invalidation on source file change — stale thumbnails served after edits. |
| P1 | ~~CACHE-011~~ | `DiskCacheManager.save` silently swallows write errors. |
| P1 | MEM-003 | Settings allow a 20 GB memory cache limit with no runtime cap against physical memory. |
| P1 |  ~~NAME-005~~ | `upadateCacheDisk()` typo. |
| P1 | TEST-003 | `#expect(true)` placeholder tests provide false confidence. |
| P1 | TEST-004 | No tests for `ScanFiles`, `CullingModel`, `SettingsViewModel`, `ExecuteCopyFiles`. |
| P1 | BUILD-002 | xcodebuild targets `x86_64` only — Apple Silicon builds are not produced. |

### ⚠️ WARN items (address in next iteration)

| Priority | ID | Issue |
|---|---|---|
| P2 | ARCH-004 | `CullingModel` missing `@MainActor` annotation. |
| P2 | CONC-007 | `.onChange` tasks not stored/cancelled on view disappear. |
| P2 | CONC-009 | `SettingsViewModel.init` race before first `Task` completion. |
| P2 | CACHE-005 | Disk cache has no size-based eviction. |
| P2 | CACHE-010 | `SharedMemoryCache.ensureReady()` lacks `setupTask` idempotency guard. |
| P2 | SCAN-004 | EXIF extraction blocks actor during scan. |
| P2 | PERS-002 | JSON write on main thread may stall for large catalogs. |
| P2 | ERR-006 | Memory pressure critical events logged only at debug level. |
| P2 | RSYNC-006 | rsync process failure not surfaced to user. |
| P2 | MEM-005 | Multiple `DiskCacheManager` instances operate on same directory. |
| P2 | NAME-002 | Non-idiomatic property names (`issorting`, `creatingthumbnails`, …). |
| P2 | NAME-003 | `asyncgetsettings()` naming violates Swift async conventions. |
| P2 | TOOL-005 | SwiftLint not integrated into `Makefile`/CI. |
| P2 | TOOL-010 | No GitHub Actions CI workflow. |
| P2 | BUILD-003 | `VERSION` not sourced from Xcode project. |

### ✅ Strengths worth preserving

- **Actor-based concurrency model** is well thought out: I/O actors, shared singleton cache, `FileHandlers` injection.
- **`DiscardableThumbnail`** implementation (access counting with `OSAllocatedUnfairLock`) is exemplary.
- **Memory pressure response** (three-level: normal / warning / critical) is production-quality.
- **Disk cache age-based pruning** is implemented and surfaced in Settings UI.
- **Security-scoped resource handling** in `ScanFiles` uses `defer` correctly.
- **`SonyThumbnailExtractor`** correctly hops off the actor thread via `withCheckedThrowingContinuation` + `DispatchQueue.global`.
- **Swift Testing framework** adoption is modern and correct.
- **Distribution pipeline** in `Makefile` (notarize + staple + DMG) is complete.

---

*End of static analysis report. Generated by GitHub Copilot — 2026-02-21.*