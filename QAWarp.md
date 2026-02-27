# Quality Assurance Report — RawCull

> **Report date:** 2026-02-27
> **Repository:** https://github.com/rsyncOSX/RawCull
> **Tag:** version-1.0.9
> **Primary language:** Swift 6 — macOS 26 Tahoe, SwiftUI + AppKit
> **Tooling in repo:** SwiftLint · SwiftFormat · Periphery
> **Analysed by:** Independent code review (Oz / Warp)

Each finding is classified as:
- ✅ **PASS** — meets expectation
- ⚠️ **WARN** — works, but has a known weakness worth addressing
- ❌ **FAIL** — concrete defect or anti-pattern that should be fixed
- ℹ️ **INFO** — neutral observation / design note

---

## Table of Contents

1. [Repository Layout & Hygiene](#1-repository-layout--hygiene)
2. [Architecture & MVVM Boundaries](#2-architecture--mvvm-boundaries)
3. [Swift Concurrency](#3-swift-concurrency)
4. [Thumbnail Pipeline & Caching](#4-thumbnail-pipeline--caching)
5. [File Scanning & Metadata](#5-file-scanning--metadata)
6. [Persistence Layer (JSON / Culling)](#6-persistence-layer-json--culling)
7. [rsync Integration (Copy Pipeline)](#7-rsync-integration-copy-pipeline)
8. [Error Handling & Logging](#8-error-handling--logging)
9. [SwiftUI View Layer](#9-swiftui-view-layer)
10. [Memory Management](#10-memory-management)
11. [Security & Sandbox](#11-security--sandbox)
12. [Naming & Code Style](#12-naming--code-style)
13. [Tooling Configuration](#13-tooling-configuration)
14. [Test Suite](#14-test-suite)
15. [Build & Distribution](#15-build--distribution)
16. [Summary & Priority Backlog](#16-summary--priority-backlog)

---

## 1. Repository Layout & Hygiene

| ID | Finding | Status |
|---|---|---|
| LAYOUT-001 | Source tree is well-partitioned: `Actors/`, `Enum/`, `Model/`, `Views/`, `Extensions/` — consistent and idiomatic for a macOS SwiftUI app. | ✅ PASS |
| LAYOUT-002 | `SupportedFileType`, `ThumbnailError`, and `WindowIdentifier` have been extracted to their own files under `Extensions/` (previously embedded in other files). Good refactoring. | ✅ PASS |
| LAYOUT-003 | `.DS_Store` files are committed inside `RawCull/` and `RawCull/Model/` and `RawCull/Views/`. The `.gitignore` lists `.DS_Store` but these were committed before the rule was added. | ⚠️ WARN |
| LAYOUT-004 | Several file headers reference `RsyncUI` as the project name instead of `RawCull` (e.g. `ArgumentsSynchronize.swift`, `Params.swift`, `Viewmodifiers.swift`, `CreateStreamingHandlers.swift`). Indicates copy-paste from the sibling project. | ⚠️ WARN |
| LAYOUT-005 | `Enum/` folder contains `SonyThumbnailExtractor` and `EmbeddedPreviewExtractor` — these are stateless caseless enums used as namespaces, not enumerations. The folder name is misleading. | ⚠️ WARN |
| LAYOUT-006 | No `Package.swift` / Swift Package Manager manifest. Pure Xcode project. Acceptable for a macOS-only app. | ℹ️ INFO |

---

## 2. Architecture & MVVM Boundaries

| ID | Finding | Status |
|---|---|---|
| ARCH-001 | MVVM separation is clear: Views are thin, ViewModels own observable state, actors handle background work. `RawCullViewModel` is `@Observable @MainActor`. | ✅ PASS |
| ARCH-002 | `CullingModel` is now `@Observable @MainActor` (previously unflagged). Thread safety is enforced. | ✅ PASS |
| ARCH-003 | `ExecuteCopyFiles` is `@Observable @MainActor` and uses `weak var sidebarRawCullViewModel` to prevent retain cycles. | ✅ PASS |
| ARCH-004 | `RawCullViewModel.abort()` is a no-op (comment: "Implementation deferred"). The `MenuCommands` UI exposes this to users. Pressing abort does nothing. | ❌ FAIL |
| ARCH-005 | `GridThumbnailViewModel` holds optional references to `RawCullViewModel` and `CullingModel`. The `open()` method sets them, but `guard self.viewModel != nil` runs _after_ the assignment — the nil check always passes. This guard provides no real protection against use-before-set from Views. | ⚠️ WARN |
| ARCH-006 | `FocusDetectorMaskModel` is `@Observable` and `@unchecked Sendable`. The `CIContext` is documented as thread-safe (correct), but the class being both `@Observable` and `@unchecked Sendable` is fragile — future mutations could silently violate thread safety. | ⚠️ WARN |
| ARCH-007 | `FileHandlers` struct is passed across actor boundaries but is not explicitly `Sendable`. It contains closures annotated `@MainActor @Sendable`, which is correct. Consider adding `: Sendable` conformance to the struct for documentation clarity. | ⚠️ WARN |

---

## 3. Swift Concurrency

| ID | Finding | Status |
|---|---|---|
| CONC-001 | Heavy I/O (scanning, thumbnail extraction, disk cache) is correctly isolated in actors. `ScanFiles`, `DiskCacheManager`, `ScanAndCreateThumbnails`, `ExtractAndSaveJPGs` are all actors. | ✅ PASS |
| CONC-002 | `RawCullView` uses `.task(id: viewModel.selectedSource)` but spawns an inner `Task(priority: .background)` inside it. The inner task is **not** cancelled when `.task(id:)` cancels the outer task — rapid source changes can leave stale scans running. | ❌ FAIL |
| CONC-003 | `.onChange(of: viewModel.sortOrder)` and `.onChange(of: viewModel.searchText)` create unretained `Task(priority: .background)` instances. No handle is stored; rapid changes produce concurrent overlapping tasks that may return stale results. | ⚠️ WARN |
| CONC-004 | `SettingsViewModel.init()` calls `loadSettings()` inside a `Task`. If `SettingsViewModel.shared` is accessed before that task completes, default values are returned. No synchronisation guard (e.g., `setupTask` pattern) exists. | ⚠️ WARN |
| CONC-005 | `ScanAndCreateThumbnails.preloadCatalog` and `ExtractAndSaveJPGs.extractAndSaveAlljpgs` both check `Task.isCancelled` at each iteration and call `group.cancelAll()`. Correct cancellation propagation. | ✅ PASS |
| CONC-006 | `DiskCacheManager.load` and `.save` use `Task.detached` with explicit priority, capturing only value types. Correct pattern — avoids retaining the actor. | ✅ PASS |
| CONC-007 | `SharedMemoryCache.memoryCache` is `nonisolated(unsafe) let NSCache` — correct because `NSCache` is internally thread-safe. Well-documented with a comment. | ✅ PASS |
| CONC-008 | `CacheDelegate._evictionCount` uses `nonisolated(unsafe) var` protected by `NSLock`. Safe but low-level. Consider `OSAllocatedUnfairLock` for consistency with `DiscardableThumbnail`. | ℹ️ INFO |
| CONC-009 | `@preconcurrency import AppKit` and `@preconcurrency import ImageIO` in `EmbeddedPreviewExtractor.swift` and `SaveJPGImage.swift` suppress strict sendability warnings. Track for removal when Apple adopts strict concurrency annotations. | ⚠️ WARN |
| CONC-010 | `SharedMemoryCache.ensureReady()` uses a boolean `isConfigured` guard. Two concurrent calls could both read `isConfigured == false` and both configure. The actor serialises them, so the second is merely redundant — but the `setupTask` pattern (already used in `RequestThumbnail` and `ScanAndCreateThumbnails`) would be more idiomatic. | ⚠️ WARN |
| CONC-011 | `KeyPath<FileItem, String>: @unchecked @retroactive Sendable` is a global retroactive conformance in `RawCullView.swift` L5. This is a known workaround for SwiftUI `Table` columns, but retroactive `Sendable` conformances on types from other modules are technically undefined behaviour and could clash with future Swift stdlib changes. | ⚠️ WARN |

---

## 4. Thumbnail Pipeline & Caching

| ID | Finding | Status |
|---|---|---|
| CACHE-001 | Layered lookup order: RAM (`NSCache`) → Disk → Live extraction. Correct and efficient. | ✅ PASS |
| CACHE-002 | Disk cache key is MD5 of the standardized file path. MD5 is appropriate for non-security keying. | ✅ PASS |
| CACHE-003 | **No file-modification-date check when loading from disk cache.** If a source ARW file is replaced after caching, the stale thumbnail is served indefinitely. | ❌ FAIL |
| CACHE-004 | Disk cache pruning (`pruneCache(maxAgeInDays:)`) is implemented and exposed in the Settings UI. | ✅ PASS |
| CACHE-005 | Disk cache has no maximum size cap — only age-based pruning. A user who never prunes could accumulate unbounded cached thumbnails. | ⚠️ WARN |
| CACHE-006 | `DiscardableThumbnail` correctly implements `NSDiscardableContent` with `OSAllocatedUnfairLock`-guarded `(isDiscarded, accessCount)`. Exemplary implementation. | ✅ PASS |
| CACHE-007 | Memory cache cost uses actual pixel dimensions from `image.representations` with a configurable bytes-per-pixel plus a 10% overhead buffer. Accurate model. | ✅ PASS |
| CACHE-008 | `CacheDelegate` tracks eviction counts via `NSCacheDelegate` and surfaces them through `CacheStatisticsView`. Good observability. | ✅ PASS |
| CACHE-009 | Memory pressure monitoring (`DispatchSourceMemoryPressure`): `.warning` → reduce to 60%, `.critical` → clear all + 50 MB minimum. Strong implementation. | ✅ PASS |
| CACHE-010 | `ScanAndCreateThumbnails` has request coalescing via `inflightTasks` dictionary. Prevents duplicate extraction for the same URL. | ✅ PASS |
| CACHE-011 | Each `ScanAndCreateThumbnails` and `RequestThumbnail` instance creates its own `DiskCacheManager()`. Multiple instances operate on the same disk directory independently — no coordination. | ⚠️ WARN |
| CACHE-012 | JPEG quality for disk cache is hardcoded at `0.7` in `DiskCacheManager.writeImageToDisk`. Acceptable default; not user-configurable. | ℹ️ INFO |

---

## 5. File Scanning & Metadata

| ID | Finding | Status |
|---|---|---|
| SCAN-001 | `ScanFiles.scanFiles` correctly calls `startAccessingSecurityScopedResource()` and wraps the scope in `defer { url.stopAccessingSecurityScopedResource() }`. | ✅ PASS |
| SCAN-002 | Directory enumeration uses `.skipsHiddenFiles`. | ✅ PASS |
| SCAN-003 | `ScanFiles` filters only `.arw` files. `SupportedFileType` enum also lists `jpeg`/`jpg` but `tiff`/`tif` are commented out. The `DiscoverFiles` actor also only uses `arw`. Behaviour is consistent within the scanning layer, though the enum has unused cases. | ⚠️ WARN |
| SCAN-004 | EXIF extraction (`extractExifData`) runs per-file inside a `withTaskGroup` — the extraction itself is concurrent, which is good for large catalogs. | ✅ PASS |
| SCAN-005 | EXIF extraction failure returns `nil` without any logging. Diagnostic blindspot for troublesome files. | ⚠️ WARN |
| SCAN-006 | `ScanFiles.sortFiles` is `@concurrent nonisolated` — correctly runs off-actor for performance. | ✅ PASS |
| SCAN-007 | `DiscoverFiles.discoverFiles` does not call `startAccessingSecurityScopedResource()`. It relies on callers having already obtained the scope. This contract is not documented. | ⚠️ WARN |

---

## 6. Persistence Layer (JSON / Culling)

| ID | Finding | Status |
|---|---|---|
| PERS-001 | `CullingModel` persists tagged/rated file records to JSON via `WriteSavedFilesJSON`/`ReadSavedFilesJSON`. Simple and appropriate for this scale. | ✅ PASS |
| PERS-002 | `WriteSavedFilesJSON` is called synchronously on the main thread via `CullingModel.toggleSelectionSavedFiles`. For very large `savedFiles` arrays this could stall the main thread. | ⚠️ WARN |
| PERS-003 | `ReadSavedFilesJSON` and `WriteSavedFilesJSON` both use the `DecodeEncodeGeneric` package. Error handling uses `do/catch` with logging. | ✅ PASS |
| PERS-004 | `SavedFiles.Equatable` implementation compares only `dateStart` and `catalog`, ignoring `filerecords`. Two `SavedFiles` with different records but same catalog/date are considered equal. This is intentional (keyed by catalog) but could surprise future maintainers. | ℹ️ INFO |
| PERS-005 | `FileRecord` properties (`fileName`, `dateTagged`, `dateCopied`, `rating`) are all optionals. This makes the model very permissive — a `FileRecord` where everything is `nil` is valid. Consider making `fileName` non-optional. | ⚠️ WARN |

---

## 7. rsync Integration (Copy Pipeline)

| ID | Finding | Status |
|---|---|---|
| RSYNC-001 | `ExecuteCopyFiles` uses `weak var sidebarRawCullViewModel` to prevent retain cycles. | ✅ PASS |
| RSYNC-002 | Security-scoped resources for source/destination are correctly accessed via bookmarks with fallback. `cleanup()` calls `stopAccessingSecurityScopedResource()` on both URLs. | ✅ PASS |
| RSYNC-003 | The include-filter file is written to `Documents/copyfilelist.txt` — a fixed path. Only one copy operation is supported at a time, which is enforced by the UI state. | ℹ️ INFO |
| RSYNC-004 | `ArgumentsSynchronize.argumentsSynchronize` has a comment "This is a hack, need to remow [sic] the two last empty arguments". The hack works but is fragile. | ⚠️ WARN |
| RSYNC-005 | rsync process execution failure calls `Logger.process.errorMessageOnly(...)` but **does not call `onCompletion`** with an error result. The UI receives no feedback about the failure. | ❌ FAIL |
| RSYNC-006 | `RemoteDataNumbers` has a hardcoded `false ? .ver3 : .openrsync` at line 98. This always selects `.openrsync`. If this is intentional, replace with just `.openrsync`. | ⚠️ WARN |

---

## 8. Error Handling & Logging

| ID | Finding | Status |
|---|---|---|
| ERR-001 | `ThumbnailError` is a typed `LocalizedError` with meaningful `errorDescription` values. | ✅ PASS |
| ERR-002 | `DiskCacheManager.save()` now uses `do { try ... } catch { Logger.process.warning(...) }`. Previously flagged; now fixed. | ✅ PASS |
| ERR-003 | **`Logger.process.errorMessageOnly()` is `#if DEBUG` only.** Errors logged via this method are invisible in Release builds. This affects `SettingsViewModel`, `ReadSavedFilesJSON`, `WriteSavedFilesJSON`, `ExecuteCopyFiles`, and `SaveJPGImage`. | ❌ FAIL |
| ERR-004 | `HistogramView.swift` line 53 uses `fatalError("Could not initialize CGImage from NSImage")` inside a `.task` modifier. **This will crash the production app** if the CGImage conversion fails. Should use a `guard ... else { return }` like the `.onChange` handler at line 41. | ❌ FAIL |
| ERR-005 | Memory pressure handler logs only at debug level (`Logger.process.debugMessageOnly`). Critical pressure events should log unconditionally at `.warning` or `.error`. | ⚠️ WARN |
| ERR-006 | `FocusDetectorMaskModel` line 24 uses `print(...)` instead of `Logger.process`. Inconsistent with the rest of the codebase. | ⚠️ WARN |

---

## 9. SwiftUI View Layer

| ID | Finding | Status |
|---|---|---|
| UI-001 | Root navigation uses `NavigationSplitView` with sidebar / content / detail — idiomatic for macOS. | ✅ PASS |
| UI-002 | `SettingsView` uses `@Environment(SettingsViewModel.self)` — properly injected. | ✅ PASS |
| UI-003 | `FileContentView` accepts `AnyView` for the `filetable` parameter. This erases SwiftUI's type information and disables compiler optimisations. Replace with a generic `Content: View` parameter and `@ViewBuilder`. | ⚠️ WARN |
| UI-004 | `MetadataValue.id` computes `UUID()` on every access. This means SwiftUI treats every render as a new identity — causing unnecessary re-renders and potential animation glitches. Store the `id` at init time instead. | ❌ FAIL |
| UI-005 | The `if` View extension (`func \`if\`<Content: View>`) conditionally applies modifiers by returning different view types. This can cause view identity discontinuities in SwiftUI — the inspector will be destroyed and recreated when the condition toggles. Consider using `.opacity(0)` or a direct `if/else` inside the body. | ⚠️ WARN |
| UI-006 | `CacheStatisticsView` polls stats via an `AsyncStream` timer every 5 seconds with proper structured concurrency cancellation. | ✅ PASS |
| UI-007 | `RawCullApp.performCleanupTask()` only logs a debug message. No cache flush or settings save on shutdown. Data is safe only because `WriteSavedFilesJSON` is called synchronously on each toggle, but in-flight settings changes could be lost. | ⚠️ WARN |
| UI-008 | Memory warning flash animation (`withAnimation(.repeatForever)`) never resets `memoryWarningOpacity` to its initial value when `memorypressurewarning` returns to `false`. The overlay disappears (via `if`), but if it reappears, the animation state may be stale. | ⚠️ WARN |
| UI-009 | `MessageView` duplicates its body for `.dark` and `.light` color schemes, differing only in text color (`.green` vs `.blue`). Consolidate using a ternary on `colorScheme`. | ⚠️ WARN |
| UI-010 | `handlePickerResult` calls `url.startAccessingSecurityScopedResource()` but never calls `stopAccessingSecurityScopedResource()` on the URL. The security scope is leaked for the lifetime of the process. It should be stored and released when the source is removed. | ❌ FAIL |
| UI-011 | `ConditionalGlassButton` uses `if #available(macOS 26.0, *)` — the deployment target is macOS 26, so the `else` branch is dead code. | ℹ️ INFO |
| UI-012 | `ZoomableFocusePeekCSImageView` and `ZoomableFocusePeekNSImageView` contain near-identical zoom/pan gesture logic. Extract a shared `ZoomableContainer` view. | ⚠️ WARN |

---

## 10. Memory Management

| ID | Finding | Status |
|---|---|---|
| MEM-001 | `DiscardableThumbnail` correctly uses `NSDiscardableContent`; NSCache can discard items under pressure. | ✅ PASS |
| MEM-002 | Memory pressure monitoring responds to `.warning` (60%) and `.critical` (clear + 50 MB). | ✅ PASS |
| MEM-003 | Settings slider allows 3,000–20,000 MB for `memoryCacheSizeMB`. `validateSettings()` logs a warning when exceeding 80% of physical RAM but **does not clamp the value**. A user on a 8 GB machine could set 20 GB and the cache will attempt to allocate it (NSCache is advisory, but the intent is misleading). | ⚠️ WARN |
| MEM-004 | `CacheConfig.production` defines 500 MB / 1000 items, but `SharedMemoryCache.ensureReady()` recalculates from `SettingsViewModel` (default 5000 MB / 10000 items). The `.production` config is effectively never used in production — only in tests. Naming is misleading. | ⚠️ WARN |

---

## 11. Security & Sandbox

| ID | Finding | Status |
|---|---|---|
| SEC-001 | App sandbox is enabled: `com.apple.security.app-sandbox = true`. | ✅ PASS |
| SEC-002 | The entitlements file only contains the sandbox flag. `com.apple.security.files.user-selected.read-write` and `com.apple.security.assets.pictures.read-only` are absent. File access relies on user-selected folder access via `fileImporter` (which grants implicit read-write). | ℹ️ INFO |
| SEC-003 | `PrivacyInfo.xcprivacy` is present and declares File API and Disk Space API access with appropriate reasons. | ✅ PASS |
| SEC-004 | Security-scoped URL access in `ScanFiles` is correctly bracketed with `defer stop`. | ✅ PASS |
| SEC-005 | `ExecuteCopyFiles.cleanup()` correctly calls `stopAccessingSecurityScopedResource()` on both source and destination URLs. | ✅ PASS |
| SEC-006 | MD5 is used for disk cache key derivation via `CryptoKit.Insecure.MD5`. Non-security use is explicitly clear from the naming. | ✅ PASS |

---

## 12. Naming & Code Style

| ID | Finding | Status |
|---|---|---|
| NAME-001 | Most types follow `UpperCamelCase` consistently. | ✅ PASS |
| NAME-002 | Several properties use non-idiomatic casing: `issorting` (→ `isSorting`), `creatingthumbnails` (→ `creatingThumbnails`), `showcopytask` (→ `showCopyTask`), `remotedatanumbers` (→ `remoteDataNumbers`), `memorypressurewarning` (→ `memoryPressureWarning`). | ⚠️ WARN |
| NAME-003 | `asyncgetsettings()` does not follow Swift naming conventions. The `async` keyword at the call site already conveys asynchrony. Rename to `getSettings()` or `currentSettings()`. | ⚠️ WARN |
| NAME-004 | `ActorCreateOutputforView` is poorly named — it formats rsync output strings, not "views". Consider `RsyncOutputFormatter`. | ⚠️ WARN |
| NAME-005 | `SharedMemoryCache.updateCacheDisk()` log message says "found in RAM Cache" but it's tracking disk hits. Copy-paste bug in the log string at `SharedMemoryCache.swift:319`. | ❌ FAIL |
| NAME-006 | `SupportedFileType` has both `jpeg` and `jpg` as separate enum cases producing different raw values. These represent the same format. Consider a single case with both extensions in the `extensions` computed property. | ⚠️ WARN |

---

## 13. Tooling Configuration

### SwiftLint

| ID | Finding | Status |
|---|---|---|
| TOOL-001 | `force_unwrapping` and `force_cast` opted-in. Good safety net. | ✅ PASS |
| TOOL-002 | `unused_declaration` enabled alongside Periphery — two layers of dead-code detection. | ✅ PASS |
| TOOL-003 | `discouraged_optional_boolean` is commented out. `Bool?` is used in some model types. Consider enabling. | ⚠️ WARN |
| TOOL-004 | SwiftLint is not run as part of the `Makefile` build pipeline. Requires manual invocation. | ⚠️ WARN |

### Periphery

| ID | Finding | Status |
|---|---|---|
| TOOL-005 | `retain_public: false` — good for a single-target app; will catch unused public declarations. Previously this was `true`; now improved. | ✅ PASS |
| TOOL-006 | Periphery is not integrated into the `Makefile`. | ⚠️ WARN |

### CI

| ID | Finding | Status |
|---|---|---|
| TOOL-007 | No GitHub Actions workflow is present. All quality gates (lint, format, test) must be run manually. | ⚠️ WARN |

---

## 14. Test Suite

### Coverage

| File | Suite | Approx. tests |
|---|---|---|
| `ThumbnailProviderTests.swift` | `RequestThumbnailTests`, `RequestThumbnailPerformanceTests` | ~12 |
| `ThumbnailProviderAdvancedTests.swift` | Memory, Stress, Edge Case, Config, Discardable, Scalability, Integration | ~20 |
| `ThumbnailProviderCustomMemoryTests.swift` | Custom Limits, Memory Pressure, Config Comparison, Eviction, Realistic | ~15 |

All tests use Swift Testing framework (`import Testing`, `@Suite`, `@Test`, `#expect`).

| ID | Finding | Status |
|---|---|---|
| TEST-001 | Swift Testing framework used consistently. Modern approach. | ✅ PASS |
| TEST-002 | Tests cover `RequestThumbnail`, `ScanAndCreateThumbnails`, `SharedMemoryCache`, `DiscardableThumbnail`, and `CacheConfig`. Good cache-layer coverage. | ✅ PASS |
| TEST-003 | **Multiple `#expect(true)` placeholder tests** that always pass: `ThumbnailProviderTests.swift:103`, `:114`, `:204`; `ThumbnailProviderAdvancedTests.swift:246`; `ThumbnailProviderCustomMemoryTests.swift:79`, `:185`. These provide no coverage value and false confidence. | ❌ FAIL |
| TEST-004 | **No tests for**: `ScanFiles`, `CullingModel`, `SettingsViewModel`, `ExecuteCopyFiles`, `DiskCacheManager`, `EmbeddedPreviewExtractor`, `SonyThumbnailExtractor`, `DeepDiveTagsViewModel`, `FocusDetectorMaskModel`. Only the cache/thumbnail layer is tested. | ❌ FAIL |
| TEST-005 | `ThumbnailProviderTests.swift:183` asserts `config.totalCostLimit == 200 * 2560 * 2560` but `CacheConfig.production` is defined as `500 * 1024 * 1024` (524,288,000 bytes). These values are not equal — **this test should fail unless the config was changed after the test was written**. Either the test or the config is wrong. | ❌ FAIL |
| TEST-006 | `createTestImage()` free function is defined in `ThumbnailProviderTests.swift` and re-used across all three test files. `createTestImages()` and `createMemoryConfig()` helpers are in `ThumbnailProviderAdvancedTests.swift`. Move to a shared `TestHelpers.swift`. | ⚠️ WARN |
| TEST-007 | Several stress tests (`rapidSequentialOperations`, `highConcurrencyStatistics`) only assert `hitRate >= 0` or `hits >= 0` — trivially true. They detect crashes but not correctness issues. | ⚠️ WARN |
| TEST-008 | No integration test exercises the full pipeline: scan → create thumbnail → cache → retrieve. | ⚠️ WARN |
| TEST-009 | Many tests create a `RequestThumbnail` or `ScanAndCreateThumbnails` instance (e.g. `let provider = ...`) but never use it — the test only interacts with `SharedMemoryCache.shared`. The local variable generates an unused-variable warning. | ⚠️ WARN |

---

## 15. Build & Distribution

| ID | Finding | Status |
|---|---|---|
| BUILD-001 | `Makefile` provides `build`, `debug`, `sign-app`, `notarize`, `staple`, `prepare-dmg`, and `clean` targets — a complete manual distribution pipeline. | ✅ PASS |
| BUILD-002 | xcodebuild destination is now `platform=OS X,arch=arm64`. Fixed from the previously-reported x86_64 issue. | ✅ PASS |
| BUILD-003 | `VERSION = 1.0.9` is hardcoded in the `Makefile` and must be manually bumped. Not sourced from the Xcode project. | ⚠️ WARN |
| BUILD-004 | `check` target has a hardcoded notarytool submission ID (`f62c4146-...`). Debug leftover. | ⚠️ WARN |
| BUILD-005 | `create-dmg` is referenced as `../create-dmg/create-dmg` — a relative path outside the repo. Fragile dependency. | ⚠️ WARN |
| BUILD-006 | The `notarize` target uses `--keychain-profile "RsyncUI"`. Note: this is named after the sibling project, not "RawCull". | ℹ️ INFO |

---

## 16. Summary & Priority Backlog

### ❌ Critical FAIL items

| Priority | ID | Issue |
|---|---|---|
| P0 | ERR-004 | `HistogramView` uses `fatalError()` in `.task` — **will crash production** if CGImage conversion fails. |
| P1 | ERR-003 | `errorMessageOnly()` is `#if DEBUG` only — errors are invisible in Release builds. |
| P1 | CONC-002 | `.task(id:)` wraps an inner unretained `Task` — defeats auto-cancellation, rapid source changes leave stale scans. |
| P1 | UI-010 | `handlePickerResult` leaks security-scoped resource access (never calls `stopAccessing`). |
| P1 | CACHE-003 | No disk cache invalidation on source file change — stale thumbnails served after edits. |
| P1 | UI-004 | `MetadataValue.id` returns new `UUID()` per access — causes SwiftUI re-render storms. |
| P1 | TEST-005 | `CacheConfig.production` assertion doesn't match actual values — test may be silently wrong. |
| P1 | ARCH-004 | `abort()` is a no-op exposed in the UI menu. |
| P1 | RSYNC-005 | rsync process failure not surfaced to user via `onCompletion`. |
| P1 | NAME-005 | `updateCacheDisk()` log message claims "RAM Cache" — misleading diagnostics. |
| P1 | TEST-003 | `#expect(true)` placeholder tests give false coverage confidence. |
| P1 | TEST-004 | No tests for scan, culling, settings, copy, or metadata layers. |

### ⚠️ WARN items (address in next iteration)

| Priority | ID | Issue |
|---|---|---|
| P2 | CONC-003 | `.onChange` tasks not stored/cancelled on rapid changes. |
| P2 | CONC-004 | `SettingsViewModel.init` race before settings `Task` completion. |
| P2 | CONC-010 | `SharedMemoryCache.ensureReady()` lacks `setupTask` idempotency pattern. |
| P2 | CONC-011 | Retroactive `@unchecked Sendable` on `KeyPath` — fragile. |
| P2 | CACHE-005 | Disk cache has no size-based eviction. |
| P2 | CACHE-011 | Multiple `DiskCacheManager` instances for same directory. |
| P2 | PERS-002 | JSON write on main thread may stall for large catalogs. |
| P2 | ERR-005 | Memory pressure critical events logged at debug level only. |
| P2 | UI-003 | `FileContentView` uses `AnyView` — loses SwiftUI optimisations. |
| P2 | UI-005 | Conditional `if` view modifier causes view identity discontinuity. |
| P2 | UI-012 | Duplicated zoom/pan gesture logic across zoom views. |
| P2 | NAME-002 | Non-idiomatic property names (`issorting`, `creatingthumbnails`, …). |
| P2 | TOOL-004 | SwiftLint not in Makefile/CI. |
| P2 | TOOL-007 | No GitHub Actions CI workflow. |
| P2 | BUILD-003 | `VERSION` not sourced from Xcode project. |
| P2 | LAYOUT-003 | `.DS_Store` files committed to repo. |

### ✅ Strengths worth preserving

- **Actor-based concurrency model** is well thought out: I/O actors, shared singleton cache, `FileHandlers` injection.
- **`DiscardableThumbnail`** implementation (access counting with `OSAllocatedUnfairLock`) is exemplary.
- **Memory pressure response** (three-level: normal / warning / critical) is production-quality.
- **Request coalescing** in `ScanAndCreateThumbnails.resolveImage` via `inflightTasks` prevents duplicate work.
- **Disk cache age-based pruning** is implemented and surfaced in Settings UI.
- **Security-scoped resource handling** in `ScanFiles` and `ExecuteCopyFiles` uses `defer` correctly.
- **`SonyThumbnailExtractor`** correctly hops off the actor thread via `withCheckedThrowingContinuation` + `DispatchQueue.global`.
- **Swift Testing framework** adoption is modern and consistent across all test files.
- **Distribution pipeline** in `Makefile` (notarize + staple + DMG) is complete and functional.
- **Focus detection** via custom Metal kernel (`Kernels.ci.metal`) with Laplacian edge detection is a sophisticated feature.
- **`DeepDiveTagsView`** metadata inspector is well-structured with recursive EXIF/XMP parsing and a clean UI.
- **ETA estimation** in `ScanAndCreateThumbnails` uses a rolling average of recent processing times — provides stable, non-jumping estimates.

---

*End of QA report — 2026-02-27*
