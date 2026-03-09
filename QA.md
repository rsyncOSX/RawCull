# QA Review

Date: 2026-03-09

Scope: manual code review of the current repository state plus one `xcodebuild test` run against `RawCull.xcodeproj`.

## Findings

### 1. High: source changes can leave stale scans running and let old results overwrite new selection state

Files:
- `RawCull/Views/RawCullSidebarMainView/RawCullView.swift:154`
- `RawCull/Model/ViewModels/RawCullViewModel.swift:100`

`RawCullView` uses `.task(id: viewModel.selectedSource)`, which would normally cancel the previous task when the selected catalog changes. That protection is bypassed by immediately spawning an unstructured `Task(priority: .background)` inside the task body.

Impact:
- Switching catalogs quickly can keep the old scan alive.
- The old scan can continue mutating `files`, `filteredFiles`, `focusPoints`, `scanning`, and thumbnail preload state after the user has already selected a different catalog.
- This is a correctness bug, not just a performance issue.

Recommendation:
- Remove the inner `Task` and `await viewModel.handleSourceChange(url:)` directly from the `.task(id:)` body.
- If background priority is important, move that choice into the async work itself while keeping the work structured and cancellable.

### 2. Medium: histogram view still hard-crashes on images that cannot produce a `CGImage`

File:
- `RawCull/Views/FileViews/HistogramView.swift:50`

The `.onChange` path handles `cgImage(forProposedRect:)` failure gracefully, but the initial `.task` path still calls `fatalError("Could not initialize CGImage from NSImage")`.

Impact:
- Any image representation mismatch or transient decode failure during first render crashes the whole app.
- The same condition is already treated as recoverable in the update path, so the startup path is inconsistent.

Recommendation:
- Replace `fatalError` with the same guarded early return used in `.onChange`.
- Log once and show an empty histogram rather than terminating the process.

### 3. Medium: runtime cache sizing is not bounded against physical memory

File:
- `RawCull/Actors/SharedMemoryCache.swift:101`

`calculateConfig(from:)` converts the user-selected MB value straight into `NSCache.totalCostLimit`. There is no runtime cap based on `ProcessInfo.processInfo.physicalMemory`.

Impact:
- A user can configure a cache substantially larger than available RAM.
- The OS will eventually push back, but only after the app creates unnecessary memory pressure and churn.
- This is especially risky for a thumbnail-heavy workflow that already reacts to memory pressure events.

Recommendation:
- Clamp the configured cache size to a fraction of physical memory, for example 50-70%.
- Keep the user setting as an upper bound, not an unconditional allocation target.

### 4. Medium: shutdown cleanup is still effectively missing

File:
- `RawCull/Main/RawCullApp.swift:16`
- `RawCull/Main/RawCullApp.swift:44`
- `RawCull/Main/RawCullApp.swift:108`

`applicationWillTerminate(_:)` is empty, while the app depends on `.onDisappear` of the main window to run `performCleanupTask()`. That cleanup method currently only logs a message and does not stop memory-pressure monitoring, flush settings, or coordinate background work shutdown.

Impact:
- Cleanup depends on window lifecycle rather than app termination lifecycle.
- Forced termination or alternate shutdown paths can skip cleanup entirely.
- This increases the chance of lost settings updates or noisy background teardown behavior.

Recommendation:
- Move real cleanup into `applicationWillTerminate(_:)`.
- Stop memory monitoring and explicitly persist settings there if those are required invariants.

### 5. Medium: test suite is no longer aligned with production cache config

Files:
- `RawCull/Model/Cache/CacheConfig.swift:16`
- `RawCullTests/ThumbnailProviderTests.swift:178`

Today’s test run built successfully but failed 1 of 49 tests:

- `RequestThumbnailTests/productionConfigLimits()`

Failure:
- expected `200 * 2560 * 2560` (`1310720000`)
- actual `CacheConfig.production.totalCostLimit` is `500 * 1024 * 1024` (`524288000`)

Impact:
- CI/local test signal is degraded because the suite currently reports failure even when the app compiles.
- The failure suggests either the test expectation is stale or `CacheConfig.production` changed without updating test coverage and rationale.

Recommendation:
- Decide which value is authoritative.
- Update either `CacheConfig.production` or the test expectation, and document why that production limit is correct.

## Verification

Command run:

```bash
xcodebuild test -project RawCull.xcodeproj -scheme RawCull -derivedDataPath /tmp/RawCullDerivedData
```

Result:
- Build completed.
- Tests passed: 48
- Tests failed: 1
- Failing test: `RequestThumbnailTests/productionConfigLimits()`

xcresult:
- `/tmp/RawCullDerivedData/Logs/Test/Test-RawCull-2026.03.09_11-20-37-+0100.xcresult`

## Overall Assessment

The codebase is structurally in reasonable shape, but there are still a few correctness issues around task lifetime, crash handling, and operational cleanup. The highest-priority fix is the unstructured source-scan task, because it can produce stale UI state during normal use. The test suite is also close to green, but it currently contains at least one stale or disputed expectation that should be resolved before treating it as a reliable release gate.
