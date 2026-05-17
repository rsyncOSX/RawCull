# Test Coverage Verification — RawCull

## What Is Tested (13 test files, ~90+ individual tests)

| Test File | What It Covers | Tags |
|-----------|---------------|------|
| `SonyMakerNoteParserTests` | TIFF binary walk → focus tag 0x2027/0x204A, DSC header skip, sensor sanity, all rejection paths | — |
| `NikonMakerNoteParserTests` | AFInfo2 binary parsing (Z9/Z8 variants), embedded JPEG SubIFD walk, all rejection paths | — |
| `SharpnessScoringTests` | `robustTailScore`, `microContrast`, `isoScalingFactor`, `ApertureHint` mapping, `SharpnessScoringModel.maxScore` normalization, concurrent `scoreFiles` guard | `.smoke`, `.threadSafety` |
| `SimilarityScoringTests` | Distance ordering, empty/missing anchor, subject-mismatch penalty, cancellation/reset state | `.smoke` |
| `ThumbnailProviderTests` | `RequestThumbnail` cache stats, missing-file nil return, clear/reset, preload; `CacheConfig` limits; `CachedThumbnail.cost` formula | — |
| `ThumbnailLoaderConcurrencyTests` | Slot saturation, cancelled waiter doesn't consume a slot, FIFO grant, `cancelAll` drains queue | `.threadSafety` |
| `CancellableImageIOWorkTests` | Cancelled tasks: Sony/Nikon thumbnail throws `CancellationError`, Sony/Nikon JPEG extraction returns nil, pre-decode phase gate | `.critical` |
| `ComparisonGridNavigationTests` | Arrow-key navigation in 1-column/2-column grids, boundary clamping, invalid index returns nil | — |
| `RawCullViewModelSecurityScopeTests` | Security-scoped URL acquire/release lifecycle, duplicate-start guard, idempotent stop, failed-start cleanup | `.smoke` |
| `RawCullViewModelZoomOverlayTests` | Zoom overlay nav-axis selection (loupe vs. other modes), mode-switch closes overlay, burst mode state | `.smoke` |
| `RawCullTestsConcurrencyTests` | `SharedMemoryCache` counter coherency (memory + grid + disk hits), `SettingsViewModel` round-trip JSON, `MemoryViewModel` stats update | `.smoke` |
| `RawCullTestsDataRaceDetectionTests` | TSan-oriented: concurrent pressure reads, concurrent cache reads+writes (memory + grid), diagnostic counter coherency, 10k-op extreme load | `.threadSafety`, `.performance` |
| `ScanAndExtractJPGsTests` | Unsupported-format files are counted as processed (progress accounting) | — |

---

## Missing Tests — Gaps That Should Be Addressed

### 1. `SonyMakerNoteParser` — `embeddedJPEGLocations` and `readEmbeddedJPEGData` (High Priority)

**What's missing:** `SonyMakerNoteParserTests` only tests `focusLocation(from:)`. The `embeddedJPEGLocations(from:)` and `readEmbeddedJPEGData(at:from:)` methods are the binary fallback path used when ImageIO fails on ARW 6.0 / RA16 files (A7 V body). This path runs in production on every A7 V file but has zero test coverage.

**Why it matters:** The fallback path bypasses ImageIO entirely; a regression would silently return no thumbnail for A7 V owners.

**Why synthetic fixtures work:** The parser is a pure binary reader; a synthetic ARW blob (same approach as the existing `makeSyntheticARW`) can embed IFD1/IFD2 JPEG offsets and verify correct offset extraction.

---

### 2. `ScanFiles.sortFiles` (High Priority)

**What's missing:** `ScanFiles.sortFiles(_:by:searchText:)` is `nonisolated static` — a pure filter+sort transformation over `[FileItem]`. It has multiple sort keys (date, name, size, rating) and a text-search path, but no tests at all.

**Why it matters:** The sort/filter pipeline determines what the user sees in every view mode. A regression (wrong sort direction, search not matching on extension) would affect every catalog load.

**Why synthetic fixtures work:** `FileItem` is a plain value type; test data can be constructed directly without any file I/O.

---

### 3. `RawCullViewModel+Culling` — Rating logic (Medium Priority)

**What's missing:** `passesRatingFilter(_:)`, `rebuildRatingCache()`, and `applySharpnessThreshold(_:)` contain non-trivial branching logic (rating levels, threshold percentile conversion) but are not tested.

**Why it matters:** Rating filter determines which files appear in `.ratedGrid` and `.comparisonGrid` modes; a bug here silently hides or shows wrong files.

**Why testable without files:** These methods only operate on in-memory `FileItem` arrays and `Int` rating values.

---

### 4. `CullingModel` — Persistence round-trip and debounced save (Medium Priority)

**What's missing:** No tests for `updateRating`, `mergeScoringResults`, or the JSON round-trip via `ReadSavedFilesJSON`/`WriteSavedFilesJSON`. `SettingsViewModelPersistenceTests` shows this pattern works for settings; a parallel test using an isolated temp file would cover culling data.

**Why it matters:** Ratings are the primary user output of the app. A serialization regression would cause work loss.

---

### 5. `DiskCacheManager` and `FullSizeJPGDiskCache` (Medium Priority)

**What's missing:** No tests for disk load/save/prune operations, MD5 key generation, or cache-size calculation. `ThumbnailProviderTests` tests the in-memory layer but not the disk layer.

**Why testable:** `makeIsolatedCache(name:config:)` in `TestIsolationHelpers` already sets up temp directories; disk actors could be initialized against those same directories.

---

### 6. `ScanAndCreateThumbnails` — Scan-side admission invariant (Medium Priority)

**What's missing:** The scan-side invariant — that this actor must *never* admit thumbnails to `memoryCache` directly (only to `gridThumbnailCache`) — is the core correctness property of the cache architecture and has no test.

**Why it matters:** If the invariant breaks, RAM hit rate degrades to ~0% on large catalogs because scan evicts UI-loaded thumbnails (boomerang miss pattern).

**Gap note:** Testing this fully requires an isolated `SharedMemoryCache`; the isolation helpers in `TestIsolationHelpers` already provide this.

---

### 7. `ScanAndExtractJPGsTests` — Only 1 test exists (Low–Medium Priority)

**What's missing:** Only the "unsupported files are counted" case is tested. Missing: cancellation terminates the loop and resets state; progress reporting; cache-hit skip path.

---

### 8. `RawFormatRegistry` — Format dispatch (Low Priority)

**What's missing:** `format(for:)` (extension → RawFormat conformer lookup) and `allExtensions` are not tested. This is a thin registry but is the entry point for all format dispatch; wrong extension registration would silently ignore files.

---

## Out of Scope for Unit Tests

These areas are intentionally excluded from the Swift Testing unit target. They
should not be added as low-value tests unless the code gains meaningful
branching, state transitions, or business logic. Behavior-focused view-model
tests remain in scope; pure SwiftUI layout/rendering tests do not.

| Area | Reason |
|------|--------|
| Pure SwiftUI view rendering/layout | No business logic; validate through UI testing if needed |
| `RawCullApp` entry point | SwiftUI `@main`; not testable in isolation |
| `SonyThumbnailExtractor` / `NikonThumbnailExtractor` full pipeline | Requires real hardware-produced ARW/NEF files; cancellation IS tested in `CancellableImageIOWorkTests` |
| `FocusMaskModel.generateFocusMask` / `computeSharpnessScore` full pipeline | Requires real CGImage + Metal compute; the numeric primitives (`robustTailScore`, `microContrast`, `isoScalingFactor`, `ApertureHint`) are fully tested |
| `DiscoverFiles` | Trivial `FileManager.enumerator` wrapper, no branching, no state |
| `SaveJPGImage` | Straightforward async file write; marginal logic |
| `ExecuteCopyFiles` / rsync integration | Requires live rsync process — belongs in a separate integration test target |
| `GridThumbnailViewModel` | Pure UI state holder, no business logic |
| `MemoryDiagnosticsViewModel` | Aggregates cache diagnostics for display only; counters are tested in `RawCullTestsConcurrencyTests` |
| `FocusPointsModel` | Immutable value type with two trivial computed properties; implicitly validated by parser tests |

---

## Summary

| Status | Notes |
|--------|-------|
| Well-covered | Parsers (Sony + Nikon), cache concurrency, scoring math, similarity, zoom/nav state, thread safety |
| Partially covered | `SonyMakerNoteParser` (missing JPEG locations), `ScanAndExtractJPGs` (1 test only), `RequestThumbnail` (no disk layer) |
| Should be added | `ScanFiles.sortFiles`, `RawCullViewModel+Culling` logic, `CullingModel` persistence, `DiskCacheManager`/`FullSizeJPGDiskCache`, `ScanAndCreateThumbnails` admission invariant |
| Intentionally not covered | Pure view rendering/layout, App entry, full image pipelines requiring real RAW files, trivial wrappers |
