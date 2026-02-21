# Code Quality Analysis — RawCull

> **Analysis date:** 2026-02-20 14:15:20  
> **Analysed by:** GitHub Copilot  
> **Repository:** [rsyncOSX/RawCull](https://github.com/rsyncOSX/RawCull)  
> **Primary language:** Swift (macOS, SwiftUI + AppKit)

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Repository Structure](#2-repository-structure)
3. [Architecture & Design Patterns](#3-architecture--design-patterns)
4. [Concurrency Model](#4-concurrency-model)
5. [Caching Strategy](#5-caching-strategy)
6. [Data Layer & Persistence](#6-data-layer--persistence)
7. [View Layer (SwiftUI)](#7-view-layer-swiftui)
8. [Testing](#8-testing)
9. [Tooling & Code Quality Gates](#9-tooling--code-quality-gates)
10. [Naming Conventions](#10-naming-conventions)
11. [Error Handling](#11-error-handling)
12. [Security & Sandbox Compliance](#12-security--sandbox-compliance)
13. [Strengths](#13-strengths)
14. [Areas for Improvement](#14-areas-for-improvement)
15. [Summary Scorecard](#15-summary-scorecard)

---

## 1. Project Overview

RawCull is a macOS-native photo-culling application written in Swift/SwiftUI. Its purpose is to allow photographers to quickly browse, tag, rate, and export Sony ARW RAW files. Key capabilities include:

- Scanning directories for `.arw` files and extracting EXIF metadata.
- Generating and caching thumbnails (RAM + disk) for fast browsing.
- Extracting full-size embedded JPEG previews from ARW files.
- Tagging/rating photos and copying selected files via `rsync`.
- A multi-window UI: main culling view, zoom window (CGImage and NSImage flavours), and a grid thumbnail window.

The project is very young (first commit: January 2026) and is under active, rapid development.

---

## 2. Repository Structure

```
RawCull/
├── Actors/           # Swift actors for async, isolated work units
│   ├── ActorCreateOutputforView.swift
│   ├── DiskCacheManager.swift
│   ├── DiscoverFiles.swift
│   ├── ExtractAndSaveJPGs.swift
│   ├── ScanAndCreateThumbnails.swift
│   ├── ScanFiles.swift
│   ├── SaveJPGImage.swift
│   ├── SharedMemoryCache.swift
│   └── RequestThumbnail.swift
├── Enum/             # Static-method namespaces via enum (caseless)
│   ├── SonyThumbnailExtractor.swift
│   └── EmbeddedPreviewExtractor.swift
├── Extensions/       # Swift extensions (String, Date, Logger, Thread)
├── Main/             # App entry point, window definitions, SupportedFileType
├── Model/            # ViewModels, JSON persistence, rsync integration, handlers
│   ├── ViewModels/
│   ├── JSON/
│   ├── Handlers/
│   └── ParametersRsync/
└── Views/            # SwiftUI views, organised by feature
    ├── RawCullView/
    ├── GridView/
    ├── FileViews/
    ├── TaggingGridView/
    ├── ThumbnailViews/
    ├── ZoomViews/
    ├── Modifiers/
    ├── Settings/
    └── Tools/
RawCullTests/         # Unit/integration tests (Swift Testing framework)
```

The directory layout is **clear and purposeful**. Grouping by technical role (`Actors`, `Enum`, `Extensions`, `Views`) rather than by feature is a common style in solo macOS projects and keeps related infrastructure together.

---

## 3. Architecture & Design Patterns

### 3.1 MVVM

The application follows an **MVVM** (Model-View-ViewModel) pattern throughout:

| Layer | Types |
|---|---|
| Model | `FileItem`, `SavedFiles`, `FileRecord`, `ARWSourceCatalog`, `SavedSettings`, `CacheConfig` |
| ViewModel | `RawCullViewModel`, `SettingsViewModel`, `GridThumbnailViewModel`, `CullingModel`, `ExecuteCopyFiles` |
| View | All types in `RawCull/Views/` |

ViewModels are marked `@Observable` (the modern replacement for `ObservableObject`), which is a good, up-to-date choice for macOS 14+.

`RawCullViewModel` and `SettingsViewModel` are `@MainActor`-bound, ensuring UI state mutations happen on the main thread.

### 3.2 Actor-based Concurrency

Heavy work (file scanning, thumbnail generation, JPEG extraction) is pushed into dedicated Swift `actor` types inside `RawCull/Actors/`. This is a clean separation of concerns. See section 4 for a detailed analysis.

### 3.3 Singleton Pattern

`SettingsViewModel.shared` and `SharedMemoryCache.shared` are `nonisolated static let` singletons. These are appropriate for app-wide shared state (settings, memory and disk cache). 

### 3.4 Caseless Enums as Namespaces

`SonyThumbnailExtractor` and `EmbeddedPreviewExtractor` use a caseless `enum` as a namespace for static methods — a Swift idiom for grouping static utilities without instantiation. This is valid but could be replaced by a `struct` with a `private init()` or simply a free function, and the naming convention is inconsistent (see section 10).

### 3.5 Handler / Callback Injection

`FileHandlers` (a plain struct of closures) is injected into actors so they can report progress back to the `@MainActor` UI without importing SwiftUI or holding a reference to the ViewModel. This is a clean, testable dependency-injection approach.

---

## 4. Concurrency Model

RawCull makes extensive use of Swift's structured concurrency and the `actor` model. This is one of the strongest areas of the codebase.

### 4.1 Actors

| Actor | Responsibility |
|---|---|
| `ScanFiles` | Directory scan + EXIF extraction |
| `DiscoverFiles` | Raw URL discovery (recursive/flat) |
| `ScanAndCreateThumbnails` | Preloads thumbnails for an entire catalog |
| `RequestThumbnail` | Per-URL thumbnail resolution (RAM → disk → generate) |
| `SharedMemoryCache` | Singleton `NSCache` wrapper with memory-pressure monitoring |
| `DiskCacheManager` | Reads/writes JPEG thumbnails to the Caches directory |
| `ExtractAndSaveJPGs` | Batch-extracts embedded JPEG previews from ARW files |
| `SaveJPGImage` | Saves a single `CGImage` to disk as JPEG |
| `ActorCreateOutputforView` | Converts rsync output to `RsyncOutputData` |

**Good practices observed:**

- Heavy I/O (disk reads/writes) is further offloaded from actors via `Task.detached(priority:)`, preventing actor re-entrancy stalls.
- `@concurrent nonisolated` is used on methods that do pure computation (sorting, output mapping), allowing them to run in parallel on the cooperative thread pool without actor serialisation overhead.
- Cancellation is handled explicitly: `preloadTask?.cancel()` + `group.cancelAll()` are called when a new catalog is selected.
- ETA estimation uses a rolling-average over recent per-item deltas, which is a practical approach.

**Concerns:**

- `DiscoverFiles` wraps its work in `Task.detached` *inside* an actor method. This is a `self`-capture in a detached task — since `self.supported` is read inside the detached closure and `self` refers to the actor, the compiler should warn under strict concurrency checking. The comment in `DiskCacheManager` acknowledges a similar issue with `CGImage`. Both should be replaced with a local copy of the value before the detached task.
- `SharedMemoryCache` uses `nonisolated(unsafe) let memoryCache`, which bypasses actor isolation. This is intentional (NSCache is internally thread-safe) and is well-documented in the comments. However, the eviction counter that is "tracked by CacheDelegate" is referenced but no `CacheDelegate` assignment is visible in the read code — this should be verified as wired up correctly.
- `ScanAndCreateThumbnails` and `RequestThumbnail` have very similar `ensureReady()` / `setupTask` patterns. This duplication could be extracted into a shared helper protocol or base actor.

---

## 5. Caching Strategy

The thumbnail caching is a two-level system:

```
Request thumbnail
       │
       ▼
SharedMemoryCache (NSCache, RAM)   ──hit──▶ return image
       │ miss
       ▼
DiskCacheManager (JPEG files in Caches/)  ──hit──▶ store in RAM, return
       │ miss
       ▼
enumExtractSonyThumbnail / enumextractEmbeddedPreview  ──▶ generate, store in both
```

**Strengths:**
- NSCache is used correctly with a cost-limit based on `width × height × bytesPerPixel`, which closely models actual memory consumption.
- Disk cache keys are derived from a MD5 hash of the standardised file path, avoiding filename collisions.
- Memory-pressure monitoring via `DispatchSourceMemoryPressure` is implemented in `SharedMemoryCache`, allowing the cache to react to OS memory warnings.
- `CacheConfig` struct allows the cache to be configured differently for tests vs. production.
- `DiscardableThumbnail` implements `NSDiscardableContent`, which allows NSCache to evict images under memory pressure.

**Concerns:**
- `DiskCacheManager.cacheURL(for:)` uses `Insecure.MD5` — while MD5 is intentional here (non-security use), the naming could confuse future readers. A comment explaining the choice is present and appreciated.
- There is no cache invalidation strategy when the source file changes (e.g., the file is modified on disk). The disk cache will serve a stale thumbnail unless it is manually cleared.
- The disk cache directory is never pruned automatically. Long-term use on a large photo library could accumulate gigabytes of stale cache entries.

---

## 6. Data Layer & Persistence

### 6.1 Settings

Settings are persisted as **JSON** in `~/Library/Application Support/RawCull/settings.json`. The serialisation uses a separate `SavedSettings: Codable` struct, which is a clean pattern — the `SettingsViewModel` (live state) is never directly serialised, avoiding accidental exposure of internal state.

A `validateSettings()` method is called before saving, which is a good defensive practice (implementation not shown in the sampled code but the call site is present).

### 6.2 Culling Data (Saved Files)

Tagged/rated files are persisted via `SavedFiles` and `FileRecord` structs to JSON, read/written by `ReadSavedFilesJSON` / `WriteSavedFilesJSON`. The `DecodeSavedFiles` intermediate type suggests a migration-friendly decode path (decoding into a raw DTO, then mapping), which is a sound pattern for forward compatibility.

### 6.3 Copy / rsync Integration

`ExecuteCopyFiles` integrates with an external `RsyncProcessStreaming` Swift package to run `rsync` for copying tagged files. This leverages process streaming for live progress output, which is consistent with the author's other projects (rsyncOSX).

---

## 7. View Layer (SwiftUI)

### 7.1 Composition

Views are well-decomposed into small, focused structs. Notable composition choices:

- `RawCullView` uses `NavigationSplitView` (sidebar + content + detail) — the correct pattern for macOS list-detail navigation.
- The main view is extended via `extension+RawCullView.swift`, splitting toolbar content, keyboard focus handling, and the file table into separate computed properties. This keeps the primary `body` readable at the cost of slightly scattered code.
- `FileContentView` composes a `filetableview: AnyView` parameter, which uses type erasure. This is a common workaround but can harm performance (extra boxing) and IDE tooling. A generic or protocol-based approach would be preferable.

### 7.2 Settings Fetching Pattern

Multiple view types (e.g., `PhotoItemView`, `GridThumbnailItemView`, `PhotoGridView`) call `await SettingsViewModel.shared.asyncgetsettings()` inside `.task {}` and store the result in a local `@State private var savedsettings: SavedSettings?`. This works but means:

- Each view makes an async call on appear.
- Settings are duplicated into each view's local state.
- A settings change will not automatically propagate to views that have already loaded.

Using `@Environment(SettingsViewModel.self)` (already injected at the root) directly in these views would be more idiomatic and reactive.

### 7.3 Keyboard Focus / Focus Bindings

Keyboard shortcuts are implemented via `@FocusedBinding` keys (`togglerow`, `aborttask`, `pressEnter`, `hideInspector`, `extractJPGs`). This is an advanced but correct macOS pattern for propagating first-responder actions through the scene hierarchy.

### 7.4 Zoom Views

Two separate zoomable image views exist: `ZoomableCSImageView` (for `CGImage`) and `ZoomableNSImageView` (for `NSImage`). The duplication suggests an opportunity for a single generic or protocol-based zoom view, accepting either image type.

---

## 8. Testing

Testing is performed using **Swift Testing** (the new `@Test` / `@Suite` framework introduced in Xcode 16), rather than XCTest. This is a modern choice.

### 8.1 Coverage

Tests are scoped to `RequestThumbnail` and `DiscardableThumbnail`. Three test files exist:

| File | Focus |
|---|---|
| `ThumbnailProviderTests.swift` | Initialisation, cache statistics, count limits |
| `ThumbnailProviderAdvancedTests.swift` | Memory pressure, stress (concurrency), edge cases |
| `ThumbnailProviderCustomMemoryTests.swift` | Template for custom memory-limit scenarios |

**Strengths:**
- Concurrency is tested: `withTaskGroup` and `async let` are used to stress-test concurrent statistics calls and concurrent clear operations.
- `CacheConfig.testing` static property allows deterministic, isolated test configurations.
- `createTestImage()` helper is a clean shared utility.

**Concerns:**
- Test coverage is limited to the cache layer. There are no tests for:
  - `ScanFiles` / `DiscoverFiles` (file system scanning)
  - `enumExtractSonyThumbnail` / `enumextractEmbeddedPreview` (image extraction)
  - `CullingModel` (tagging / save / reset logic)
  - `SettingsViewModel` (load / save / validate)
  - `ExecuteCopyFiles` (rsync integration)
- Several tests contain placeholder `#expect(true)` assertions, indicating scaffolding that was not yet completed.
- The comment in `ThumbnailProviderTests.swift` — *"Note: We'd need access to storeInMemory to fully test this"* — points to a testability gap: the `storeInMemory` method is private and cannot be exercised from outside the actor without refactoring.

---

## 9. Tooling & Code Quality Gates

The repository includes a solid set of quality tooling:

| Tool | Configuration File | Purpose |
|---|---|---|
| SwiftLint | `.swiftlint.yml` | Static analysis, style enforcement |
| SwiftFormat | `.swiftformat` | Automatic code formatting |
| Periphery | `.periphery.yml` | Dead code detection |
| Make | `Makefile` | Build, test, lint, format automation |

The `Makefile` is comprehensive and covers building, testing, linting, formatting, and release tasks. This is excellent for a solo project and makes CI integration straightforward.

The `.swiftlint.yml` configuration is present but its specific rules were not fully sampled — care should be taken that the ruleset is not too permissive.

---

## 10. Naming Conventions

This is the most inconsistent aspect of the codebase.

### Issues observed (all are fixed):

| Issue | Example | Recommendation |
|---|---|---|
| ~~Enum-as-namespace types use lowercase-first naming~~ | `enumExtractSonyThumbnail`, `enumextractEmbeddedPreview` | Types should be `UpperCamelCase`: `SonyThumbnailExtractor`, `EmbeddedPreviewExtractor`|
|~~Function names use~~ `snake_case` | `en_date_from_string()`, `localized_string_from_date()` | Swift convention is `lowerCamelCase` |
| ~~Inconsistent capitalisation in enum names~~ | `enumExtractSonyThumbnail` vs `enumextractEmbeddedPreview` | Standardise|
| ~~Typo in file name~~ | `exstension+String+Date.swift` | Should be `extension+String+Date.swift` |
| ~~Method name is all-lowercase~~ | `requestthumbnail(for:targetSize:)` | Should be `requestThumbnail(for:targetSize:)`|
| ~~Variable name~~ `savedsettings` | Used in many views | Should be `savedSettings`~~|
| ~~Parameter~~ `fullSize _:` (ignored parameter) | In `ExtractAndSaveJPGs.extractAndSaveAlljpgs` | Suppressed parameter should be removed or implemented|

The date-formatting extension methods inherit naming from the author's other Swift projects, but the `snake_case` style stands out in an otherwise camelCase codebase.

---

## 11. Error Handling

### Strengths:
- `ThumbnailError: LocalizedError` is a well-defined, typed error enum with descriptive messages for all three failure cases (`invalidSource`, `generationFailed`, `contextCreationFailed`).
- Do-catch blocks are used appropriately in `ScanFiles.scanFiles()` and settings persistence.
- `Logger.process.warning(...)` is used consistently to surface non-fatal errors without crashing.

### Concerns:
- Several I/O operations use `try?` silently discarding errors:
  - `DiskCacheManager.save()` → `try? Self.writeImageToDisk(...)` — a write failure is logged nowhere.
  - `FileManager.default.createDirectory(...)` in `DiskCacheManager.init()` silently ignores errors.
  - `group.waitForAll()` in `ExtractAndSaveJPGs` is called with `try?`, masking any child-task errors.
- In `ScanFiles.scanFiles()`, failed `resourceValues` calls use `try?` with a silent fallback, meaning a file with unreadable metadata is silently included with zeroed values rather than being logged or excluded explicitly.
- `performCleanupTask()` in `RawCullApp` is an empty function body (only a log message). Any future cleanup logic added here will not be guaranteed to run synchronously before app termination.

---

## 12. Security & Sandbox Compliance

- **Security-scoped resources** are correctly accessed in `ScanFiles.scanFiles()` with `url.startAccessingSecurityScopedResource()` and `defer { url.stopAccessingSecurityScopedResource() }`.
- The app has a `.entitlements` file and a `PrivacyInfo.xcprivacy` file, indicating awareness of App Sandbox and privacy manifest requirements.
- The `exportOptions.plist` is present for distribution.
- `DiskCacheManager` stores thumbnails in the standard `Caches/` directory, which is correct for data that can be regenerated.
- Settings are stored in `Application Support/`, which is correct for user-configured, persistent data.

**Concern:** `DiscoverFiles` captures `self.supported` inside a `Task.detached` closure. Under strict concurrency checking (`-strict-concurrency=complete`), this actor-isolated property access from a detached task would be a compile error. A local copy should be made before entering the detached task.

---

## 13. Strengths

1. **Modern Swift concurrency** — Pervasive, correct use of `actor`, `async/await`, `TaskGroup`, and cooperative cancellation. This is well ahead of most macOS apps of comparable scope.
2. **Clear architectural separation** — Actors handle background work; ViewModels own UI state; Views are dumb. The pattern is consistent and easy to follow.
3. **Two-level thumbnail cache** — RAM + disk caching with memory-pressure awareness is sophisticated and production-appropriate.
4. **Good observability** — `OSLog` with custom `debugMessageOnly` / `debugThreadOnly` / `errorMessageOnly` helpers makes it easy to trace concurrency issues in debug builds without impacting release performance.
5. **Modern Swift Testing** — Using the `@Test` / `@Suite` framework for tests is a forward-looking choice.
6. **Tooling** — SwiftLint, SwiftFormat, Periphery, and a comprehensive `Makefile` demonstrate engineering discipline.
7. **Privacy compliance** — Sandbox entitlements and a `PrivacyInfo.xcprivacy` file are present.
8. **Configurable cache** — `CacheConfig` decouples test configurations from production, enabling reliable unit testing.

---

## 14. Areas for Improvement

### High Priority

1. **Expand test coverage** — Only the cache layer is tested. Add tests for `ScanFiles`, `CullingModel`, `SettingsViewModel`, and the JPEG extraction enums.
2. **Fix naming conventions** — Rename caseless enums, snake_case functions, and lowercase method names to follow Swift API Design Guidelines.
3. **Silent error suppression** — Replace `try?` in fire-and-forget I/O operations with explicit error logging so failures are observable.

### Medium Priority

4. **Settings propagation in views** — Replace the `asyncgetsettings()` / local `@State` pattern with direct `@Environment(SettingsViewModel.self)` access to ensure reactivity.
5. **Disk cache pruning** — Implement a cache eviction policy (e.g., LRU or time-based) to prevent unbounded growth of the disk cache.
6. **Cache invalidation on file change** — Detect when source ARW files are modified and invalidate their cached thumbnails.
7. **Deduplicate `ensureReady()` pattern** — Extract the `setupTask: Task<Void, Never>?` lazy-initialisation pattern into a reusable helper.
8. **`AnyView` in `FileContentView`** — Replace `filetableview: AnyView` with a generic or `@ViewBuilder`-based parameter to improve type safety and SwiftUI diffing performance.

### Low Priority

9. **Fix filename typo** — Rename `exstension+String+Date.swift` → `extension+String+Date.swift`.
10. **Implement `performCleanupTask()`** — Add actual cleanup logic (e.g., cancelling pending tasks, flushing disk cache) or remove the empty function.
11. **Remove placeholder tests** — Replace `#expect(true)` stubs with real assertions or mark them as `.disabled()` with a tracking comment.
12. **Document `nonisolated(unsafe)`** — The existing comment on `SharedMemoryCache.memoryCache` is good; ensure this pattern is not cargo-culted elsewhere without the same justification.
13. **Detached task `self` capture** — Resolve the `self.supported` capture in `DiscoverFiles` and any similar patterns under strict concurrency.

---

## 15. Summary Scorecard

| Category | Score | Notes |
|---|---|---|
| Architecture & Design | ⭐⭐⭐⭐⭐ | Clean MVVM, excellent actor separation |
| Concurrency | ⭐⭐⭐⭐½ | Best-in-class use of Swift actors; minor `self`-capture concerns |
| Caching | ⭐⭐⭐⭐ | Sophisticated two-level cache; lacks invalidation & pruning |
| Data Persistence | ⭐⭐⭐⭐ | Sound JSON patterns; no migration strategy yet |
| View Layer | ⭐⭐⭐½ | Well-composed; settings pattern and AnyView usage could improve |
| Testing | ⭐⭐ | Good foundation; very limited coverage |
| ~~Naming Conventions~~ | ⭐⭐½ | Inconsistent; enum namespaces and snake_case need attention (fixed)|
| Error Handling | ⭐⭐⭐ | Good typed errors; too many silent `try?` suppressions |
| Tooling | ⭐⭐⭐⭐⭐ | Excellent: SwiftLint, SwiftFormat, Periphery, Makefile |
| Security / Sandbox | ⭐⭐⭐⭐⭐ | Security-scoped resources, entitlements, privacy manifest |

**Overall:** RawCull is a **well-engineered, modern macOS application**. The concurrency model in particular is a standout — it goes beyond what most Swift apps implement and demonstrates a strong grasp of Swift's actor model. The main areas to address as the project matures are test coverage, naming consistency, and silent error handling.