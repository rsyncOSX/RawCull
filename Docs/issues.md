# RawCull Code Review — Issues

This document reports findings from a static deep review of the RawCull
codebase (`RawCull/`, `RawCullModelDownloader/`, project/build configuration,
and Swift package pinning). The findings were reassessed against the current
implementation on 4 August 2026. The reassessment traced production call
sites, cancellation and persistence ownership, build settings, and dependency
resolution rather than accepting the original severity labels at face value.
Line numbers refer to the reviewed revision on this branch and may drift as
the code changes.

Each issue retains its originally reported **Severity** and now also has a
**Review verdict**:

- **Verified — Critical** — reachable in the shipping app and can lose or
  corrupt durable user state/output, silently fail a core copy/export, breach
  an integrity boundary, crash, or cause an action to target the wrong photo.
- **Verified — Non-Critical** — real, but limited to performance, diagnostics,
  accessibility, transient/auxiliary UI, or an unlikely edge case without a
  demonstrated durable-integrity impact.
- **Not Relevant** — contradicted by current code, unreachable in production,
  intentionally gated, test-only, or conditional on a feature the app does not
  currently support. A future-risk condition is noted where useful.

The original severity definitions were:

- **Critical** — can cause a crash, data loss/corruption, a security/integrity
  gap, or user-visible incorrect behavior in a core workflow (ratings,
  culling, copying files, image identity).
- **Non-Critical** — a code smell, inefficiency, minor UX/accessibility rough
  edge, or a real but low-probability edge case.

## Original Summary

| Area | Critical | Non-Critical |
|---|---:|---:|
| Rating / culling data integrity (cross-cutting, 4 manifestation sites) | 1 | — |
| Actors (`RawCull/Actors`) | 6 | 6 |
| AI integration, model downloads, cache, diagnostics | 2 | 6 |
| ViewModels (`RawCull/Model/ViewModels`) | 4 | 7 |
| Rsync execution, JSON persistence, handlers | 3 | 4 |
| Views — grids, comparison, zoom, sidebar, settings | 11 | 10 |
| App lifecycle & project configuration | 1 | 4 |
| **Total** | **28** | **37** |

The reviewed totals and closure priorities are at the end of this document.

---

## 0. Cross-cutting: rating state conflates "never rated" with "explicitly kept" (Critical)

**Review verdict:** Verified — Critical

**Impact verification:** This is reachable during normal sharpness scoring and
changes durable rating semantics. It affects the unrated filter and statistics,
and burst undo can persist a keeper rating for a photo the user never rated.
That is a core culling-data integrity failure, not merely a presentation issue.

This single root cause surfaces in several independent files, so it is called
out first rather than being duplicated per-file.

**Root cause —** `RawCull/Model/ViewModels/CullingModel.swift:79-84,122-140`
and `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:11-29,59-61`

```swift
// CullingModel.swift
func isUnrated(photo: String, in catalog: URL) -> Bool {
    guard let index = savedFiles.firstIndex(where: { $0.catalog == catalog }) else { return false }
    return savedFiles[index].filerecords?.contains { $0.fileName == photo } ?? false
}
```

`isUnrated` actually reports whether **any** persisted `FileRecord` exists for
a photo — not whether the user has rated it. Records are created not only by
`updateRatings`/`applyRatings` (explicit star ratings) but also by
`mergeScoringResults`, which is invoked for **every** sharpness/saliency-scored
photo and stores `rating: nil` since no explicit rating is passed. Separately,
`rebuildRatingCache()` builds `ratingCache[name] = record.rating ?? 0`, and
`getRating(for:)` returns `ratingCache[file.name] ?? 0` — so a photo that was
merely scored (never rated by the user) reads back identically to an
explicitly-set "keeper" (rating `0`).

**Justification:** Because sharpness scoring runs automatically over a
catalog as part of normal analysis (not a user action), essentially every
scanned photo ends up with a persisted record and a cached rating of `0`,
indistinguishable from a real "keeper" decision. This produces confirmed
incorrect behavior at multiple call sites:

- `RawCull/Views/CullingGrid/CullingGridView.swift:724-726` — the `.unrated`
  rating filter is `filteredFiles.filter { !isUnrated(...) }`. Once a catalog
  has been scored, `isUnrated` returns `true` for scored-but-never-rated
  photos, so they are excluded from the "Unrated" filter even though the user
  never rated them.
- `RawCull/Views/GridView/ScanStatsSheetView.swift:275-297` — `cullingStats`
  uses the same `isUnrated` check; scored-but-unrated photos fall into the
  `else` branch and, because `getRating` returns `0`, are counted as **kept**
  rather than **unrated** in the catalog summary shown to the user.
- `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:524-529,817-821`
  — burst-action undo snapshots ratings via `getRating(for:)` (which cannot
  distinguish "no record" from "explicit rating 0") and reapplies them with
  `applyRatings`, so undo can turn previously-untouched photos into
  persisted "keeper" records.
- `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift:63-74` —
  `hasRating(in:)` correctly checks `record.rating != nil`, proving the
  codebase does have a way to keep this distinction; it just isn't used
  consistently in `rebuildRatingCache`/`getRating`/`isUnrated`.

**Fix direction:** make `FileRecord.rating == nil` the one true "unrated"
signal everywhere, stop defaulting to `0` in the rating cache, and give
`isUnrated` an implementation and call sites that actually mean what its name
says.

---

## 1. Concurrency (`RawCull/Actors/`)

### RawCull/Actors/ExtractAndSaveJPGs.swift:81-122,124-197
**Title:** Cancelled export generations can corrupt the next run's state
**Severity:** Critical
**Review verdict:** Not Relevant
**Impact verification:** Production prevents overlapping use of this actor:
`startSelectedJPGExtraction` requires `currentExtractAndSaveJPGsActor == nil`
and constructs a fresh actor for every operation. Abort clears the reference,
and the next operation again creates a new instance. Late work can therefore
not mutate a later run's actor-local counters. A generation token would still
make the actor safer as a reusable API, but the reported cross-run corruption
is not reachable in the app.
**Issue:** Starting a new JPG export cancels the previous `Task` via
`cancelExtractJPGSTask()`, but does not wait for the old run's in-flight child
work to drain, and the new run immediately resets shared counters
(`successCount`, `failures`, `processingTimes`).
**Justification:** Child calls from the cancelled run (`processSingleExtraction()`,
`incrementAndGetCount()`, `save()`, `updateEstimatedTime()`) can still land on
the actor after the new run has reset its state, corrupting progress/ETA and
success/failure counts for the new export.

### RawCull/Actors/ScanAndCreateThumbnails.swift:76-140,145-299
**Title:** Cancelled preload work can bleed into the next preload
**Severity:** Critical
**Review verdict:** Not Relevant
**Impact verification:** `handleSourceChange` creates a new
`ScanAndCreateThumbnails` for each catalog load, while cancellation clears the
old `currentScanAndCreateThumbnailsActor`. No production call invokes
`preloadCatalog` twice on the same instance, so old completions cannot update
the next instance's counters. The catalog-bound handler closures also reject
updates for an inactive catalog.
**Issue:** Same pattern as above: `cancelPreload()` only cancels and nils the
task reference; a new preload resets counters immediately while old
`processSingleFile()` calls are still in flight.
**Justification:** Stale child completions from the cancelled preload can
still call `incrementAndGetCount()`, `notifyFileHandler()`, and
`updateEstimatedTime()` on the new preload's state, producing wrong progress
and file counts shown to the user.

### RawCull/Actors/ScanAndCreateThumbnails.swift:301-325
**Title:** Off-main AppKit drawing inside a background actor
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `NSImage` is not generally thread-safe, and
`lockFocus()` is deprecated. The result image is actor-confined until complete,
which lowers the risk, but the source `NSImage` may be a shared cached object.
The code should use a bitmap/`CGContext` path or otherwise enforce single-thread
image access. No reachable crash or corruption was demonstrated, so Critical is
not justified.
**Issue:** `downscale(_:to:)` calls `NSImage.lockFocus()`, `draw(in:)`, and
`unlockFocus()` from a non-`@MainActor` actor.
**Justification:** AppKit's `NSImage` drawing APIs are not documented as
thread-safe; performing them concurrently off the main actor risks corrupted
bitmaps or crashes under concurrent thumbnail generation.

### RawCull/Actors/ScanAndExtractJPGs.swift:39-82,84-150
**Title:** Cancelled JPG warmups can corrupt the next warmup run
**Severity:** Critical
**Review verdict:** Not Relevant
**Impact verification:** `startScanAndExtractJPGs` constructs a new actor for
each warmup and refuses to start while an actor is registered. Abort/catalog
cancellation drops the old instance; a later warmup uses a different actor.
The shared-counter reset race requires concurrent reuse of one actor, which no
production call site performs.
**Issue:** Same cancel-then-immediately-reuse-state pattern as the two issues
above: `cancelExtraction()` cancels and clears `extractTask`, but
`extractCatalogJPGs()` resets counters while the old task's children may still
be running.
**Justification:** Late completions from a superseded warmup can still mutate
the new run's counters/timing, producing incorrect progress/ETA.

### RawCull/Actors/SharedMemoryCache.swift:121-125,388-425
**Title:** `nonisolated(unsafe)` cache APIs bypass actor/sendability safety for `NSImage`
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The compiler guarantee is intentionally bypassed:
`CachedThumbnail` is `@unchecked Sendable` and documents a construct-once,
read-only invariant. `NSCache` protects its own container, but not mutation of
the wrapped `NSImage`. This is a real hardening concern, especially alongside
off-main image conversion, but there is no identified mutation-after-insertion
path or demonstrated crash that supports Critical impact.
**Issue:** `memoryCache`/`gridThumbnailCache` are declared `nonisolated(unsafe)`
and exposed via synchronous `object()`/`gridObject()` lookups that hand out
`NSImage`-wrapping values without an actor hop.
**Justification:** Other actors in this directory then use those AppKit
objects off-main. Safety depends entirely on informal invariants rather than
anything the compiler enforces, which is exactly the situation Swift 6 strict
concurrency is meant to catch.

### RawCull/Actors/FullSizeJPGDiskCache.swift:33-39,42-59,62-72
**Title:** Full-size cache key ignores file metadata
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The key is only schema version, standardized path,
and variant. Any source replacement at the same path can therefore reuse an old
full-size preview until cache cleanup, regardless of its new size or mtime.
**Issue:** The cache key hashes only `standardized.path` + `variant`, unlike
`ThumbnailCacheKey`, which also incorporates file size and modification date.
**Justification:** Replacing a RAW file in place (same path, new bytes) can
return a stale cached full-size JPEG for the new file.

### RawCull/Actors/SaveJPGImage.swift:51-68
**Title:** Export filenames collide on duplicate basenames
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** The destination is derived from the source stem and
mode only and uses an atomic replacing write with no existence/collision check.
The current catalog scan is flat, so the stated same-run subfolder example is
not accurate; however, two supported RAW files with the same stem and different
extensions, or exports from different catalogs into the same destination, can
silently overwrite generated output. The silent overwrite makes this a core
export-integrity issue.
**Issue:** `outputURL(...)` derives the destination filename only from
`lastPathComponent` (plus a `_demosaic` suffix), dropping the source
directory, and writes atomically with no collision detection.
**Justification:** Two source RAW files with the same basename from different
folders (a common occurrence across multiple card imports/subfolders) silently
overwrite each other's exported JPEG.

### RawCull/Actors/ThumbnailLoader.swift:81-112
**Title:** Requested thumbnail size is ignored after slot acquisition
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** After the grid fast path, every request uses
`settings.thumbnailSizePreview`; `targetSize` is not forwarded. This violates
the loader contract and can return an unnecessarily large or incorrectly sized
preview, but no durable data is affected.
**Issue:** Outside the small (`<= 200`) fast path, the loader always requests
`settings.thumbnailSizePreview` from `RequestThumbnail`, ignoring the caller's
`targetSize`.
**Justification:** Callers requesting a specific size can get back a
differently-sized image, which can also poison size-keyed caches with the
wrong dimensions.

### RawCull/Actors/DiscoverFiles.swift:14-32
**Title:** Detached scan ignores cancellation
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `Task.detached` does not inherit cancellation and the
enumeration loop never checks it. The result is discarded by canceled callers,
so the demonstrated impact is wasted filesystem work and slower teardown.
**Issue:** Directory discovery is launched with `Task.detached` (which does
not inherit the caller's cancellation) and the enumeration loop never checks
`Task.isCancelled`.
**Justification:** A cancelled scan/preload keeps enumerating the file system
and doing wasted work after its result is no longer needed.

### RawCull/Actors/DiskCacheManager.swift:89-101,153-178
**Title:** Thumbnail disk cache has no size cap
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Saves have no byte-budget eviction. The only cleanup
is explicit age pruning/clearing through `SharedMemoryCache`, so a large number
of catalogs can consume substantial disk between cleanup operations.
**Issue:** Every save persists a new JPEG; the only cleanup path is an
externally-triggered, age-based prune (`pruneCache(maxAgeInDays:)`).
**Justification:** Without a size-based eviction policy, long-running use on
large catalogs can grow the on-disk cache unbounded between prunes.

### RawCull/Actors/ExtractAndSaveJPGs.swift:129-146,158-166
**Title:** Decode failures vanish from the export result
**Severity:** Non-Critical
**Review verdict:** Verified — Critical
**Impact verification:** Embedded-preview load, JPEG encoding, and RAW
demosaic failures return without incrementing success or appending a failure.
The completion UI only reports `JPGExportResult.failures`, so an export can
finish with selected files silently absent and no incomplete-export warning.
That is a core export correctness failure and is more severe than originally
reported.
**Issue:** Several failure paths (`guard let` / `try?` on embedded-preview
extraction, JPEG encoding, RAW demosaic) return early without recording a
`JPGExportFailure`.
**Justification:** Failed files can disappear from both `succeeded` and
`failures`, so the export summary under-reports how many files actually
failed.

### RawCull/Actors/ScanFiles.swift:60-105
**Title:** Directory scan fans out one metadata task per file with no throttle
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** One task is added for each supported file without a
limiter. The cooperative executor bounds actual thread execution, but task and
metadata work can still create avoidable memory pressure on very large
catalogs.
**Issue:** The scan's task group spawns one child task per discovered file
with no bounded-concurrency limiter.
**Justification:** Very large catalogs can spawn thousands of concurrent
metadata/parsing tasks at once, increasing memory pressure and cancellation
latency compared to other actors in this directory that are more disciplined
about throttling.

---

## 2. AI Integration, Model Downloads, Cache, Diagnostics

### RawCull/Model/AIIntegration/RawCullAIModelDownloadCatalog.swift:72-82,103-117,138-152,173-187
**Title:** Production catalog does not pin downloadable model contents
**Severity:** Critical
**Review verdict:** Not Relevant (currently gated; Critical before release)
**Impact verification:** The missing hashes/revisions are real release work,
but every production descriptor has `releaseReadiness: .blocked`. The
coordinator returns `.unavailable` and rejects licence acceptance/download
before reaching the service, and release preflight also rejects these
descriptors. There is no current production path that trusts these unpinned
models. Do not change a descriptor to `.ready` until immutable provenance and
expected hashes are populated.
**Issue:** Every production model descriptor leaves `expectedArchiveSHA256`
`nil` (and two leave `upstreamRevision` unset), even though the type exists
specifically to record integrity/provenance data.
**Justification:** This is the app-owned provenance layer for
network-delivered AI models (CLIP/SAM3). Without a pinned hash/revision, the
app has no way to prove which exact bytes it is about to load are the ones it
expects. (Note: the project's `Makefile release-preflight` target does check
for `releaseReadiness: .blocked` / `expectedArchiveSHA256: nil` and blocks
release builds while this is true, so this may be intentionally incomplete
for now — but the enforcement code path itself must still be correct and
should be revisited before models ship as non-blocked.)

### RawCull/Model/AIIntegration/RawCullAIModelDownloadService.swift:149-175,190-202
**Title:** Downloaded model bundles are trusted without integrity or version checks
**Severity:** Critical
**Review verdict:** Not Relevant (currently gated; Critical before release)
**Impact verification:** `modelURL` only verifies that a directory exists, so
the service would need content/version validation before any descriptor becomes
ready. Today, all production descriptors are blocked in the coordinator and
the live source is an unconfigured `.invalid` placeholder, making this path
unreachable in the shipping configuration.
**Issue:** `download()` only confirms an asset pack with the expected
`assetPackID` exists and calls `ensureLocalAvailability`; `modelURL` only
checks that a path exists and is a directory.
**Justification:** Nothing compares the delivered bundle against the
catalog's SHA-256/byte-count/revision before the app treats it as trusted
model content. On the self-hosted (non-Apple) distribution path in
particular, a pack published under the right ID with different contents
would be accepted.

### RawCull/Model/AIIntegration/RawCullAIModelDownloadService.swift:244-274
**Title:** Explicit licence acceptance is skipped for already-installed packs
**Severity:** Non-Critical
**Review verdict:** Not Relevant (currently gated)
**Impact verification:** The ordering issue exists for a future ready model:
an installed location is accepted before the explicit-licence check. The only
descriptor requiring acceptance (SAM 3) is release-blocked, and the coordinator
checks that gate before querying installed state. There is no current model that
can bypass an applicable licence gate.
**Issue:** `snapshot()` reports `.installed` as soon as a pack is found
locally; the licence-acceptance check only runs on the fresh-download path.
**Justification:** A model restored from backup or preseeded outside of
`download()` can become usable without ever passing through the licence
gate, so the gate only protects one of the paths that lead to model use.

### RawCull/Model/AIIntegration/RawCullAIModelDownloadService.swift:156-175
**Title:** Download progress updates race with final completion state
**Severity:** Non-Critical
**Review verdict:** Not Relevant (currently gated)
**Impact verification:** A buffered status update could race the explicit
`progress(1)` callback in a future enabled download, but all production
downloads are blocked and the live manifest source is not configured. Revisit
when enabling downloads; cancel and await the progress consumer before
publishing completion.
**Issue:** A separate `progressTask` streams `.downloading` updates while the
main path later calls `progress(1)`; the updater is only cancelled in
`defer`.
**Justification:** Buffered progress events can arrive after the explicit
completion callback, so the UI can flicker back to a stale "downloading"
state after already showing "installed"/"validating".

### RawCull/Model/AIIntegration/RawCullAIModelResourceManager.swift:49-53,83-165
**Title:** Model validation cache can miss metadata-preserving tampering
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The in-process reuse key recursively snapshots path,
kind, size, mtime, and symlink target rather than bytes. A same-size,
mtime-preserving modification during the app process can reuse a previous
cryptographic validation result. This requires local write access and careful
metadata preservation, so it is a hardening edge case rather than Critical.
**Issue:** The validation cache keys on path, kind, size, modification date,
and resolved symlink target — never file content hashes.
**Justification:** In-place file changes that preserve size and mtime reuse
the cached validation result, so a corrupted/modified model bundle can be
treated as still-valid without re-validation.

### RawCull/Model/AIIntegration/DeepAIReviewFeature.swift:680-690,797-799
**Title:** Duplicate candidate IDs can crash progress construction
**Severity:** Non-Critical
**Review verdict:** Not Relevant
**Impact verification:** Production candidates are constructed from
`groupFiles`, which are resolved through unique `FileItem.id` dictionaries;
the request-building path itself also uses
`Dictionary(uniqueKeysWithValues:)` before review. Duplicate IDs would already
violate upstream invariants and trap earlier. No path that introduces a
duplicate only at `progress()` was found.
**Issue:** `progress()` builds `Dictionary(uniqueKeysWithValues: completed.map { ($0.fileID, $0) })`
without deduplicating `fileID`s first.
**Justification:** `Dictionary(uniqueKeysWithValues:)` traps on duplicate
keys; if burst assembly upstream ever produces the same `fileID` twice for a
Deep Review batch, this crashes instead of degrading gracefully.

### RawCull/Model/AIIntegration/RawCullAIModels.swift:258-297
**Title:** Saved-burst cache scan swallows per-file decode failures
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Only `skippedCacheFileCount` is retained. This makes
support diagnostics less actionable but does not affect the authoritative
cache loader or user data.
**Issue:** Non-cancellation errors while reading/decoding a cached JSON
artifact only increment a `skippedCacheFileCount`; the filename and error are
discarded.
**Justification:** Corrupt or schema-incompatible cache files become an
opaque count with no way to diagnose which file or what went wrong.

### RawCull/Model/Cache/ThumbnailCacheKey.swift:8-48,143-155
**Title:** Thumbnail keys can collide after in-place source replacement
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** A replacement that preserves standardized path, byte
count, and exact modification time reuses the key. That is technically
possible, though uncommon; adding a content digest would trade substantial I/O
for protection against this edge case.
**Issue:** Cache identity is standardized path + file size + modification
date + representation settings — not content hash.
**Justification:** Replacing a RAW file with different bytes while
preserving size and mtime (possible with some backup/sync tools) yields the
same `cacheIdentifier` and can serve a stale thumbnail for the new file.

---

## 3. ViewModels (`RawCull/Model/ViewModels/`)

(See also Section 0 for the rating-ambiguity issues in this directory.)

### RawCull/Model/ViewModels/CullingModel.swift:90-103,122-139,143-176,258-299
**Title:** Basename-only persistence keys can collide across folders
**Severity:** Critical
**Review verdict:** Not Relevant (current flat-catalog scope)
**Impact verification:** `ScanFiles.scanFiles` uses
`contentsOfDirectory` without recursion and the preload discovery path passes
`recursive: false`. A catalog therefore contains only one directory level,
where two files cannot have the same full basename (`file.name`, including the
extension). This becomes Critical if recursive/nested catalogs or aggregated
multi-folder catalogs are introduced without first changing persistence to a
catalog-relative path or stable file identity.
**Issue:** Ratings, scoring metadata, and burst-winner overrides are all
persisted keyed by `fileName`/`memberFileNames` (basenames), and callers pass
`file.name` — a basename, not a catalog-relative path or stable identifier.
`upsertRecord` matches existing rows purely by `$0.fileName == fileName`.
**Justification:** Two different RAW files with the same basename in
different subfolders of the same catalog will silently overwrite or read
each other's ratings, sharpness metadata, or manually-chosen burst winners.

### RawCull/Model/ViewModels/CullingModel.swift:197-237
**Title:** Cancelled debounced saves can still write stale snapshots
**Severity:** Critical
**Review verdict:** Not Relevant as reported
**Impact verification:** Production saves without a custom URL all go through
the single shared `WriteSavedFilesJSON` actor, whose `performWrite` contains no
suspension point, so writes are serialized and an in-progress old write cannot
finish after a newer write. The stale last-write claim is therefore not
supported for the shipping save handler. Dirty-state correctness is still
broken by `SavedFiles.==` (reviewed separately), and shutdown still fails to
flush pending work; those are the actionable persistence defects.
**Issue:** `scheduleSave()` snapshots state, cancels the previous save
`Task`, and later calls `persist(snapshot)`. `persist(_:)` only checks
`guard snapshot == savedFiles` **after** the write already happened.
**Justification:** An out-of-date snapshot can still win the last-write race
on disk even though `hasUnsavedChanges` remains `true` in memory afterward,
which can silently overwrite newer culling changes with older ones. This
compounds with the app-lifecycle issue in Section 6 — there is no call to
`flushPersistence()` anywhere in the app, including on quit.

### RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift:179-201
**Title:** New scoring requests reuse whatever batch is already running
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** A burst analysis can request a scoped batch while a
manual scoring batch is active (or vice versa). `scoreFiles` awaits the existing
task and returns without checking requested file IDs, scoring source, signature,
or configuration. The caller then persists/uses whatever scores happen to be
present and continues burst ranking with missing or wrong-scope data. This can
change automated culling recommendations.
**Issue:** `scoreFiles(_:)` awaits any existing `_scoringTask` and returns
without checking whether that in-flight task was started for the same file
set, scoring source, or configuration.
**Justification:** A second scoring request issued while another is running
never launches its own work; it silently receives results from the previous,
differently-scoped batch, which then drives ranking and persistence.

### RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:131-139
**Title:** Catalog reload can clobber unsaved culling changes
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** Catalog switching does not flush `CullingModel`, and
every completed non-empty load calls `loadSavedFiles()`, which replaces the
whole in-memory array. If this wins the race with the 350 ms debounce, later
edits can persist the reloaded stale state and permanently remove the recent
rating/override.
**Issue:** Every successful catalog load calls `cullingModel.loadSavedFiles()`,
which replaces the entire in-memory culling store from disk — even if a
debounced write from a recent rating/override edit is still pending.
**Justification:** Reloading from disk can reintroduce stale state before a
pending write completes; a subsequent save built from that stale state can
overwrite a just-made edit.

### RawCull/Model/ViewModels/FocusandSharpness/FocusPointsModel.swift:45-52
**Title:** Malformed focus metadata can produce NaN/∞ coordinates
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Four numeric fields are accepted even when sensor
dimensions are zero, and normalization divides without validation. Current
overlay code often checks finite values later, but not consistently; malformed
metadata can hide or misplace focus markers without altering stored photos.
**Issue:** `normalizedX`/`normalizedY` divide by `sensorWidth`/`sensorHeight`
without checking they are non-zero.
**Justification:** A malformed/partial EXIF AF-location string can yield zero
sensor dimensions, producing invalid coordinates that propagate into focus
overlays and downstream scoring.

### RawCull/Model/ViewModels/MemoryDiagnosticsViewModel.swift:82-83,100-109,198
**Title:** Diagnostics sampling log grows without any bound
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** A sample is appended every five seconds for the
duration of a user-started diagnostics session and the array is only reset when
a new session starts. Normal sessions are small, but a long-running console can
grow memory without a cap.
**Issue:** A new `Entry` is appended roughly every 5 seconds for as long as
logging is active; `entries` is never trimmed.
**Justification:** Long diagnostic sessions grow this array unboundedly,
which is a poor look specifically for a *memory* diagnostics tool.

### RawCull/Model/ViewModels/RawCullAISettingsModel.swift:225-237
**Title:** Cancelled model removal leaves the UI stuck in "removing" state
**Severity:** Non-Critical
**Review verdict:** Not Relevant (currently gated)
**Impact verification:** The cancellation cleanup is incomplete for a future
enabled managed-model flow. In the current production catalog every descriptor
is release-blocked before installed/removal state is exposed, so the UI cannot
start this removal path.
**Issue:** `removeManagedModel(_:)` sets `.removing` before awaiting
`coordinator.remove(id)`; a `CancellationError` returns early without
restoring prior state.
**Justification:** The row can stay stuck showing "removing" with actions
disabled until an unrelated refresh happens to repair it.

### RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:93-97 (and `RawCullViewModel.getFocusPoints()`)
**Title:** Multiple AF points for one file are dropped
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Both the main lookup and comparison lookups require
exactly one `FocusPointsModel` for a filename. Native metadata currently tends
to produce one entry, but fallback JSON or future multi-point metadata can
legitimately produce several, at which point all are hidden instead of merged.
**Issue:** Focus-point loading creates one `FocusPointsModel` per decoded
entry, but the consumer only returns data when *exactly one* model matches
the selected file's name.
**Justification:** If more than one focus-point entry exists for a file (or
basenames collide — see the identity issues elsewhere in this document), the
consumer returns `nil` and all AF overlays for that image silently disappear.
Related occurrences with the same "only exactly one/first match" pattern:
`RawCull/Views/ComparisonGridView/ComparisonGridView.swift:233-236` and
`RawCull/Views/ComparisonGridView/BurstCullingWorkspaceView.swift:492-495`.

### RawCull/Model/ViewModels/RawCullViewModel+Diagnostics.swift:4-10
**Title:** Raw diagnostics presentation has no stale-result guard
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Every request is an independent task and completion
blindly replaces a single presentation property. Rapid requests can therefore
show the older file's diagnostics after a newer request finishes.
**Issue:** `presentRawDiagnostics(for:)` launches an untracked `Task` and
unconditionally assigns `rawDiagnosticsPresentation` on completion.
**Justification:** There is no cancellation token or "is this still the
selected file" recheck, so a slower earlier request can overwrite a later
one and show diagnostics for the wrong file.

### RawCull/Model/ViewModels/SettingsViewModel.swift:194-243
**Title:** Concurrent settings saves can overwrite newer values
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `saveSettings()` is main-actor isolated but reentrant
while awaiting its detached atomic write. Two invocations can snapshot different
values and complete out of order. The scope is app preferences, not photo or
rating data.
**Issue:** `saveSettings()` snapshots properties and writes them from a
detached background task with no serialization against overlapping saves.
**Justification:** If two saves overlap, an older detached write finishing
after a newer one can put stale configuration back on disk.

### RawCull/Model/ViewModels/SimilarityScoringModel.swift:1247-1275
**Title:** Burst grouping silently drops files missing similarity artifacts
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Swift's `split(whereSeparator:)` omits separator
elements, so every file without an embedding disappears from all returned
groups. Those files should remain visible as singleton/unavailable groups. The
bug is limited to failed/incomplete similarity indexing, so the original
Non-Critical classification is appropriate.
**Issue:** `groupBursts(files:)` uses `files.split { snapshot[$0.id] == nil }`;
`split` **omits** the separator elements entirely.
**Justification:** Photos without an embedding never appear in
`burstGroups`/`burstGroupLookup`/burst-home counts, so files that failed
indexing quietly vanish from the burst workflow instead of appearing as
singleton groups.

---

## 4. Rsync Execution, JSON Persistence, Handlers

The rsync argument pipeline itself is sound: `ArgumentsSynchronize` builds a
plain `[String]` that is handed to `RsyncProcess`/`Process.arguments`, so
there is **no shell-string command injection** in this path. The
higher-impact problems here are correctness/data-integrity, not injection.

### RawCull/Model/Handlers/CreateStreamingHandlers.swift:24-35
**Title:** Rsync runtime failures are suppressed
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** The pinned `RsyncProcessStreaming` implementation only
turns a non-zero termination status into an error when
`checkForErrorInRsyncOutput` is true. Here it is false, line validation is a
no-op, and propagated errors are discarded. The termination callback still
runs and `ExecuteCopyFiles` constructs the normal completion result, so disk
full, permission, vanished-source, and I/O failures can be reported as success.
**Issue:** The streaming process handlers are configured with
`checkForErrorInRsyncOutput: false`, `propagateError: { _ in }` (discarded),
and `checkLineForError: { _ in }` (no-op).
**Justification:** `ExecuteCopyFiles` only catches *launch-time* exceptions.
A copy that fails mid-run (permission denied, disk full, I/O error, source
vanished) still completes the normal success path and is presented to the
user as a successful copy.

### RawCull/Model/JSON/ReadSavedFilesJSON.swift:38-58
**Title:** Corrupt saved-files JSON is treated like an empty store
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** Missing-file and decode-failure both become `nil`.
On startup that leaves an empty store; the next rating or scoring write can
atomically replace the corrupt but potentially recoverable file, causing
permanent loss of ratings and burst overrides without offering recovery.
**Issue:** A JSON decode failure is logged and the function returns `nil` —
the same value returned when the file simply doesn't exist yet.
**Justification:** Callers cannot distinguish "file is corrupt/schema
mismatch" from "no saved data ever existed." The app continues with an empty
in-memory store and can later overwrite the still-corrupt-but-recoverable
file, permanently losing previously saved ratings/overrides.

### RawCull/Model/JSON/SavedFiles.swift:87-96
**Title:** Equality/hashing ignore the actual persisted records
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** `CullingModel.persist` uses array equality as a
commit/dirty-state check, but `SavedFiles.==` ignores both mutable payloads.
An older completed save can therefore clear `hasUnsavedChanges` even when a
newer rating/override snapshot differs. That defeats retry/flush bookkeeping
for durable culling state.
**Issue:** `SavedFiles ==` and `hash(into:)` compare only `dateStart` and
`catalog`, ignoring `filerecords` and `burstWinnerOverrides`.
**Justification:** Two materially different saved states compare as equal.
`CullingModel.persist(_:)` (Section 3) relies on `snapshot == savedFiles` to
decide whether a save "stuck" — with this equality, a stale snapshot can be
considered equal to state that has since changed, suppressing detection of
a lost write.

### RawCull/Model/ParametersRsync/RemoteDataNumbers.swift:103-126
**Title:** Parse-failure fallback is immediately overwritten
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Control flow continues after `defaultvalues()` and
copies parser fields. In particular, `datatosynchronize` defaults back to
`true` when `numbersonly` is absent, contradicting the safe fallback. This
affects copy-preview messaging/confirmation, not the rsync argument safety.
**Issue:** When `getstats()` throws, `defaultvalues()` sets safe defaults,
but the initializer keeps reading fields from the failed parser afterward,
ending with `datatosynchronize = parsersyncoutput.numbersonly?.datatosynchronize ?? true`.
**Justification:** The "safe" fallback state doesn't stick — on a parse
failure the model can end up reporting contradictory results, including
optimistically claiming there is data to synchronize when parsing never
actually succeeded.

### RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:274-276
**Title:** Include-list cleanup failures are silently discarded
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Deletion failure is ignored and the only in-memory
URL is cleared. The file contains selected filenames rather than image bytes
and remains recoverable/cleanable from Application Support, so the original
"unrecoverable" wording overstates the impact, but orphan accumulation and
minor privacy exposure are real.
**Issue:** `cleanup()` removes the generated `copyfilelist-*.list0` file with
`try?` and clears `includeListURL` regardless of success.
**Justification:** If deletion fails, a file listing selected photo names is
left behind in Application Support with no remaining in-app reference to it
— an invisible, unrecoverable leak.

### RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:345-360
**Title:** Stale security-scoped bookmarks are never renewed
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `isStale` is populated and ignored. Resolution may
work for the current operation, but failing to regenerate bookmark data can
cause later intermittent access failures after filesystem/volume changes.
**Issue:** `bookmarkDataIsStale` is captured during resolution but never
acted on.
**Justification:** Stale bookmarks should be regenerated and re-persisted;
continuing to use one can work temporarily and then start failing
intermittently across later launches or after system/volume changes.

### RawCull/Model/JSON/WriteSavedFilesJSON.swift:29-35
**Title:** Custom save URLs bypass actor serialization
**Severity:** Non-Critical
**Review verdict:** Not Relevant (test-only in this repository)
**Impact verification:** Repo-wide call-site review found `savedFilesURL`/the
`to:` overload used only by isolated persistence tests. Production always uses
the shared writer actor, so concurrent custom-URL overwrites are not a shipping
RawCull issue. Keep serialization in mind if this injection API gains a
production caller.
**Issue:** When a caller supplies `savedFilesURL`, `write()` constructs a
brand-new `WriteSavedFilesJSON` actor instead of reusing the shared one.
**Justification:** Concurrent writes to that same injected URL are no longer
serialized against each other. Writes are individually atomic, so files
aren't torn, but an older write can still finish last and overwrite a newer
one.

---

## 5. Views — Grids, Comparison, Zoom, Sidebar, Settings

A recurring pattern across this layer: async image/search/regroup work is
launched from `.task`/`Task { }` without a cancellation check or a
"is this result still current" guard before publishing back into `@State`.
Each concrete occurrence is listed below since each needs its own fix.

### RawCull/Views/CullingGrid/CullingGridView.swift:438-460
**Title:** Batch operations can target hidden/collapsed burst frames
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** Rendering uses `shownFiles`, while selection ranges,
badge matching, and batch rating use every file in each visible group. A user
can therefore select and durably rate/reject hidden frames that were not
presented for review. This directly corrupts the intent of a culling action.
**Issue:** `visibleSelectionFiles`/`visibleSelectionIDs` flatten **every**
file in each visible burst group (`visibleBurstGroups.flatMap(\.files)`),
while the grid actually renders only `shownFiles`, a filtered subset from
`BurstGroupCleanViewPolicy.visibleFiles(...)` (used at line 561/587) when a
burst is shown in collapsed/"clean" view.
**Justification:** Verified: shift-range selection, "select matching badge,"
and batch star-rating all operate over frames the clean-view policy is
currently hiding from the user, so a rating action can be applied to photos
the user cannot see and did not consciously select.

### RawCull/Views/GridView/GridThumbnailView.swift:40-52,58-70
**Title:** Arrow-key navigation can move into off-screen burst files
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** `GridThumbnailView.sortedFiles` follows complete
burst membership rather than `BurstGroupCleanViewPolicy.visibleFiles`. The
selection can land on a collapsed member, and rating shortcuts then operate on
that hidden selected ID. This is a wrong-photo action path, not only a focus
indicator glitch.
**Issue:** Keyboard navigation walks `sortedFiles`, and in burst mode
`sortedFiles` is built directly from `viewModel.similarityModel.burstGroups`
filtered only to "is this ID in `filteredFiles`" — not the same
collapsed/clean-view subset the grid renders.
**Justification:** Left/right arrow keys can select a group member that
isn't currently on screen; subsequent single-item shortcuts (rate, reject,
etc.) then silently act on a photo the user isn't looking at.

### RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:161-176
**Title:** Toolbar zoom buttons desynchronize the pinch-gesture baseline
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Toolbar handlers change `scale` without changing
`lastScale`; the keyboard handlers correctly update both. The next pinch can
snap to the stale baseline. This is reproducible interaction breakage but does
not target another photo or alter durable state, so Critical is overstated.
**Issue:** `onZoomOut`/`onZoomIn` mutate `viewModel.scale` directly but never
update `viewModel.lastScale`, while `MagnifyGesture().onChanged` computes
`scale = lastScale * value.magnification`.
**Justification:** Verified: after zooming with the toolbar +/- buttons, the
next pinch gesture starts from the stale pre-button `lastScale` and the image
snaps to an unexpected size — a visible, reproducible interaction bug.

### RawCull/Views/ZoomViews/ZoomOverlayView.swift:719-739,845-850
**Title:** Button/keyboard zoom leave gesture state out of sync
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `increaseZoom`/`decreaseZoom` update `currentScale`
only, while the gesture multiplies `lastScale`. The next gesture jumps. The
effect is confined to transient viewport state.
**Issue:** Same pattern as above: the overlay's zoom helpers change
`currentScale` without updating `lastScale`, which the pinch gesture uses as
its baseline.
**Justification:** Zooming via toolbar or keyboard shortcuts causes the next
pinch gesture to snap to an unexpected scale.

### RawCull/Views/ZoomViews/ZoomOverlayView.swift:410-420,821-825
**Title:** Stale focus mask can remain over a newly-selected photo
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** Selection change calls `reload()` without first
canceling/clearing `maskTask` and `focusMask`. The old mask is still rendered
when `showFocusMask` is on until delayed regeneration finishes, presenting
analysis evidence for one photo on another. Because focus evidence drives the
core culling decision, this remains Critical under the review rubric.
**Issue:** Navigating to another image reloads the preview and resets
zoom/source state, but does not clear `focusMask` first.
**Justification:** The previous image's focus-mask overlay can remain
visible on top of the newly-loaded photo until the delayed mask
regeneration completes, visibly misattributing focus evidence to the wrong
image.

### RawCull/Views/ZoomViews/ImageSourceToggleView.swift:26-34
**Title:** RAW-unavailable fallback can get stuck on an unusable source
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** If the previous/selected source is `.developedRAW`,
`resetForNewImage` stores the same unavailable source as `previous`, and
failure assigns it back. No source-selection change is emitted to trigger a
JPEG/thumbnail reload, leaving a blank preview. This blocks viewing but does
not damage source or culling data.
**Issue:** `resetForNewImage()` copies the current source into `previous`.
If the newly-selected file's developed-RAW preview fails,
`markDevelopedRAWUnavailable()` falls back to that same `previous` value,
which can itself be `.developedRAW`.
**Justification:** When the fallback target is also unavailable, the logic
never escapes to JPEG/thumbnail, and the preview can get stuck showing
nothing for that image.

### RawCull/Views/ThumbnailComponents/ThumbnailImageView.swift:24-49
**Title:** Thumbnail loader can publish a stale image after the source changes
**Severity:** Critical
**Review verdict:** Not Relevant as reported
**Impact verification:** `.task(id:)` is structured and SwiftUI cancels the old
task when the URL changes. Both `ThumbnailLoader` and `RequestThumbnail`
re-check cancellation after suspension; canceled coalesced waiters return
`nil`. The state should still be cleared at task start to avoid briefly showing
the old thumbnail while the new one loads, but the claimed late stale repaint
path is guarded in the current loaders.
**Issue:** `.task(id:)` keeps the previous thumbnail in state, awaits
`loadThumbnail()`, and unconditionally writes the result back with no
cancellation check and no clearing of old state first.
**Justification:** A slow load for a previous selection can complete after
a newer selection has already started loading, repainting the view with the
wrong photo's thumbnail.

### RawCull/Views/ThumbnailComponents/FileTableRowView.swift:109-113
**Title:** Search updates can race and overwrite newer results
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Each change starts an independent sort using a
snapshot of the query, and there is no task identity/cancellation check before
assigning `filteredFiles`; completion order can differ from typing order. The
table can show an older query, but the rows remain visible before the user acts,
so no direct durable-integrity impact was demonstrated.
**Issue:** Every keystroke starts a fresh, untracked `Task` calling
`handleSearchTextChange()` with no cancellation of the previous search task.
**Justification:** An older, slower text search can finish after a newer one
and overwrite `filteredFiles`, leaving the table showing results for a query
the user already changed away from.

### RawCull/Views/ComparisonGridView/ComparisonGridView.swift:59-63,202-220
**Title:** Source-toggle / bulk-load reloads can publish stale images
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** Source toggles create independent reload tasks. An
older reload can finish last and put the wrong representation under a file's
label; the bulk `.task(id:)` also assigns the coordinator's partial dictionary
after cancellation. Rating controls continue to target the labelled file ID,
so stale pixels can cause a rating to be applied to a different photo than the
one the user believes is displayed.
**Issue:** Toggling JPG/thumbnail source and the initial bulk `loadImages()`
both launch untracked `Task`s and write results back into `imageStates`
without checking whether the source/request is still current, including
after the coordinator itself detected cancellation and returned a partial
dictionary.
**Justification:** Rapid source toggling or navigating away mid-load can
leave the comparison grid showing an outdated or incomplete image/focus-data
set for the currently selected files.

### RawCull/Views/SavedFiles/SavedFilesView.swift:9-17,76-80,147-149
**Title:** Selection stores copied structs instead of stable IDs
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `@State` retains value snapshots, so the Saved Files
detail columns do not live-update after model mutations. This auxiliary viewer
can show stale metadata until reselection, but its selections do not write
ratings or modify files; Critical is not supported.
**Issue:** `selectedCatalog`/`selectedRecord` store whole `SavedFiles`/
`FileRecord` **value** snapshots in `@State`, rather than an identifier
resolved live from the model.
**Justification:** Because these are value types, the selection is frozen at
selection time. Subsequent rating changes, copy-date updates, resets, or
persistence updates to `viewModel.cullingModel.savedFiles` are not reflected,
so the detail pane can show stale data for the "selected" item.

### RawCull/Views/Modifiers/FileInspectorView.swift:65-73
**Title:** Histogram can show the previous file's data after selection changes
**Severity:** Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The old `nsImage` is not cleared when the task ID
changes. Even with cancellation-aware thumbnail loading, the old histogram is
shown during the new load and indefinitely if the new load fails. This is
misleading auxiliary analysis, but it has no direct write/data-loss path.
**Issue:** The thumbnail-loading task only assigns `nsImage` on success and
never clears it first when the selected file changes or the load fails.
**Justification:** `HistogramView` keeps rendering the previous file's
histogram — a form of misleading analysis data — until a new thumbnail
successfully arrives.

### RawCull/Views/ComparisonGridView/ComparisonImageLoader.swift:24-34
**Title:** Thumbnail sharpening ignores parent-task cancellation
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The detached sharpening operation continues after
its caller is canceled and does not check cancellation before returning. The
coordinator discards canceled results, so the impact is wasted CPU/I/O and
slower resource release.
**Issue:** Sharpening runs via `Task.detached`, immediately awaited; detached
tasks do not inherit the parent's cancellation.
**Justification:** Leaving the comparison view or changing selection
mid-sharpen leaves the detached work running and burning CPU/I/O for a
result that will be discarded.

### RawCull/Views/CandidateInspectorView.swift:130-145,203-207 *(`RawCull/Views/ComparisonGridView/CandidateInspectorView.swift`)*
**Title:** Duplicate evidence strings can disappear from the inspector
**Severity:** Non-Critical
**Review verdict:** Not Relevant
**Impact verification:** Current `RawCullCore` producers append each fixed
reason/caution at most once, and Deep Review explicitly deduplicates issues.
No production producer supplies duplicate strings within any one `ForEach`
input. Index-based identity would be more defensive for externally decoded or
future data, but no current evidence row can disappear for this reason.
**Issue:** Reason/caution lists render with `ForEach(items, id: \.self)` over
raw, non-deduplicated `[String]`.
**Justification:** Repeated strings produce duplicate SwiftUI identities,
which can cause rows to be collapsed/reused incorrectly and hide real
evidence lines from the reviewer.

### RawCull/Views/Modifiers/ButtonStyles.swift:134-144
**Title:** Pressed-state animation has overlapping, uncancelled reset timers
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Release creates an untracked delayed task and no task
handle is retained. Rapid clicks can let an older timer reset a newer press's
visual state; the effect is cosmetic.
**Issue:** Every button release spawns a new sleep-then-reset `Task` without
cancelling earlier ones.
**Justification:** Rapid repeated clicks create competing timers where an
older task can end a newer press's hold-animation window early, producing
visibly jittery feedback.

### RawCull/Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:37-50,146-148
**Title:** Filtered-empty state reports the catalog itself as empty
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The empty branch reads the local `files` property,
which is `viewModel.filteredFiles`, not the scanned `viewModel.files`. Active
filters with zero matches therefore show the wrong empty-catalog explanation.
**Issue:** The "No Files Found" branch is driven by `viewModel.filteredFiles.isEmpty`,
not the unfiltered catalog contents.
**Justification:** If active rating/search/semantic filters simply match
nothing, the UI incorrectly tells the user the folder has no RAW images at
all and suggests picking a different catalog.

### RawCull/Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:135-143
**Title:** Stored scan-progress closure is never cleared
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The view stores a closure capturing its `@State`
storage in a longer-lived view model and has no `onDisappear` cleanup. Later
assignments normally replace it, but an inactive view can be retained/updated
unnecessarily.
**Issue:** The view assigns a closure to `viewModel.countingScannedFiles`
that captures this view's `@State`, with no matching cleanup on disappear.
**Justification:** The callback can outlive the view and continue targeting
now-stale state, or hold a reference longer than necessary.

### RawCull/Views/SimilarityGridView/SimilarityGridSelectionView.swift:15,77-85
**Title:** Debounced regroup task survives view removal
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The task is canceled only by a later schedule, not on
disappear. It can start an unnecessary regroup after navigation; generation
handling inside the similarity model limits stale commits.
**Issue:** Regrouping is deferred into an unstructured `Task` that is only
cancelled when a *newer* regroup is scheduled, not when the view disappears.
**Justification:** Leaving the similarity screen inside the debounce window
can still trigger `viewModel.reGroupBursts()` from an inactive screen.

### RawCull/Views/ThumbnailComponents/FileTableRowView.swift:67-76
**Title:** Rejected and keeper ratings render identically to unrated rows
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Only 2–5 star values have a distinct rendering.
Rejected, explicit keeper, and never-rated all show four empty stars, hiding
important state but not modifying it.
**Issue:** The table's rating column only draws filled stars for values 2-5;
rejected (`-1`) and keeper (`0`) both fall through to the same empty-star
display as a truly unrated row.
**Justification:** The table view hides real, meaningful state
(rejected vs. kept vs. unrated) from the user at a glance.

### RawCull/Views/Settings/SettingsResetSaveButtons.swift:68-73
**Title:** "Save" action is styled as destructive
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The confirmation button declares `.destructive` for
a normal save. This produces misleading semantics/styling only.
**Issue:** `Button("Save", role: .destructive, ...)` applies destructive
role/styling to a normal save action.
**Justification:** Misleading visual and accessibility semantics for a
routine, non-destructive action.

### RawCull/Views/ThumbnailComponents/RatingFilterButtons.swift:27-36
**Title:** Color-only filter buttons lack accessible names
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** The circle-only rejected/star buttons have no
accessible text or explicit label; `.help` is not a reliable VoiceOver name.
This blocks an assistive-technology path but does not affect stored data.
**Issue:** The rejected/star filter controls are plain colored `Circle()`
views with only a `.help(...)` tooltip, no accessibility label/trait.
**Justification:** VoiceOver cannot reliably announce what each button
filters by, making this control unusable for assistive-technology users.

### RawCull/Views/Tools/MenuCommands.swift:12-23
**Title:** "Actions" menu items stay enabled with no focused target
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** Optional focused bindings silently ignore assignment
when no scene provides a value, yet the commands are always enabled. This is a
minor command-state/feedback defect.
**Issue:** Commands rely on `@FocusedBinding` but are never disabled when no
window publishes those focused values.
**Justification:** Menu items that visually appear actionable can silently
no-op in windows that don't wire up the corresponding focused value.

---

## 6. App Lifecycle & Project Configuration

### RawCull/Main/RawCullApp.swift:57-73,108-111
**Title:** Closing the main window can quit the app without flushing pending culling saves
**Severity:** Critical
**Review verdict:** Verified — Critical
**Impact verification:** `flushPersistence()` has no call sites. Main-window
disappearance performs only synchronous security-scope cleanup and immediately
terminates; `applicationWillTerminate` is empty. A rating made inside the 350 ms
debounce window can be lost on close/quit. Explicit termination also closes
secondary windows even when they would otherwise keep the app alive.
**Issue:** The main "Photo Culling" `Window`'s `.onDisappear` unconditionally
calls `performCleanupTask()` (which only calls
`viewModel.stopActiveSecurityScopedAccess()`) followed by
`NSApplication.shared.terminate(nil)`. `applicationWillTerminate(_:)` in
`AppDelegate` is empty. `CullingModel.flushPersistence()` — the method that
exists specifically to force a pending debounced save to complete — is never
called from anywhere in the app (verified via repo-wide search).
**Justification:** `CullingModel.scheduleSave()` debounces writes by ~350ms
(`saveDelayNanoseconds`). If the user rates/tags a photo and then closes the
main window (or the window closes as a side effect of quitting), the pending
save's `Task` has no guarantee of completing before the process exits, since
nothing flushes it first — risking silent loss of the most recent rating or
culling decision. Separately, `applicationShouldTerminateAfterLastWindowClosed`
already returns `true`, so terminating explicitly on the *main* window's
disappearance also means secondary windows (Memory Console, Similarity
Console, About) are force-closed the moment the main window closes, even if
the user only meant to close that one window and keep a diagnostics window
open.

### RawCull.entitlements / RawCullModelDownloader/RawCullModelDownloader.entitlements
**Title:** Sandboxed targets declare no user-selected-file or network entitlements
**Severity:** Non-Critical
**Review verdict:** Not Relevant
**Impact verification:** The main target's Debug and Release build settings
both set `ENABLE_APP_SANDBOX = YES` and
`ENABLE_USER_SELECTED_FILES = readwrite`. Xcode uses that setting to synthesize
the user-selected-file sandbox entitlement even though the hand-authored plist
only contains app-group/sandbox keys. The downloader uses Background Assets,
and all model releases plus the live self-hosted source are currently blocked,
so a direct network-client entitlement is not demonstrated as necessary.
**Issue:** Both entitlements files set `com.apple.security.app-sandbox` and
an app-group, but neither declares
`com.apple.security.files.user-selected.read-write` (or `.read-only`) or
`com.apple.security.network.client`. The app clearly persists
security-scoped bookmarks across launches (`sourceBookmark`/`destBookmark` in
`ExecuteCopyFiles.swift`) and performs `.fileImporter`-based folder picking.
**Justification:** Flagged as non-critical rather than critical because this
cannot be confirmed to fail without actually running/signing the app (out of
scope for this static review — the BackgroundAssets-based model downloader in
particular may not need `network.client` since the OS handles that
transfer). It's still worth an explicit sandboxing/entitlements audit, since
missing `files.user-selected.read-write` is a documented prerequisite for
security-scoped bookmarks to keep resolving across relaunches, which is
exactly the mechanism `ExecuteCopyFiles` depends on.

### RawCull/Extensions/extension+Thread+Logger.swift:29-33
**Title:** Error-level logging is compiled out of Release builds entirely
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical
**Impact verification:** `errorMessageOnly` is fully wrapped in `#if DEBUG`,
so its 19 current RawCull call sites emit nothing in Release. Some newer paths
use direct `Logger.warning`, but important bookmark, process-launch, settings,
and JSON error paths still lose diagnostics. This impairs supportability; it
does not itself cause the underlying failures.
**Issue:** `Logger.errorMessageOnly(_:)` (and `debugMessageOnly`/
`debugThreadOnly`) wrap their body in `#if DEBUG`, so in a Release build the
call becomes a no-op.
**Justification:** Every "failed to access folder," "executeProcess
failed," JSON-decode failure, and similar error-path log call in the entire
codebase (167 call sites) is silently discarded in the shipped app. This
makes it materially harder to diagnose a user-reported bug from Console logs,
since none of the error paths this review found (several of them
data-loss-adjacent) leave any trace in a Release build.

### RawCull/Extensions/extension+Thread+Logger.swift:52-57
**Title:** Unused helper with a latent crash on negative input
**Severity:** Non-Critical
**Review verdict:** Not Relevant
**Impact verification:** Repo-wide search confirms there are no call sites.
The conversion would trap for a negative value, but dead code cannot currently
affect users. Remove it or validate the argument before introducing a caller.
**Issue:** `Task.sleep(seconds:)` computes
`UInt64(seconds * 1_000_000_000)`, which traps if `seconds` is negative. A
repo-wide search found this helper has no call sites at all.
**Justification:** Dead code; low risk today since it's unused, but it's a
crash trap waiting for the first caller that passes a computed/negative
duration, and should either be removed or hardened (e.g. `max(0, seconds)`).

### RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
**Title:** `xgrammar` dependency is pinned to a moving branch, not a version/commit
**Severity:** Non-Critical
**Review verdict:** Verified — Non-Critical (wording corrected)
**Impact verification:** `xgrammar` is a transitive dependency and its
requirement is the `main` branch, but the checked-in `Package.resolved` also
records the exact revision `cee45aa95b8cdb5b16a8e11c037336870ec22369`.
Ordinary resolved builds are therefore reproducible. The hygiene risk appears
when intentionally updating/re-resolving the graph, where an unbounded branch
can advance without a semantic-version boundary.
**Issue:** Every other resolved package pins a semantic version or a fixed
commit SHA; `xgrammar` (`https://github.com/mlc-ai/xgrammar`) is pinned to
`branch: main`.
**Justification:** Resolving packages fresh (or running `swift package
update`) can silently pull in new, unreviewed upstream code on `main` with no
version boundary — a reproducibility and supply-chain hygiene gap compared to
every other dependency in the project.

---

## Reviewed Findings Summary and Closure Advice

### Final disposition

| Area | Verified Critical | Verified Non-Critical | Not Relevant |
|---|---:|---:|---:|
| Rating / culling data integrity | 1 | 0 | 0 |
| Actors | 2 | 7 | 3 |
| AI integration, model downloads, cache, diagnostics | 0 | 3 | 5 |
| ViewModels | 2 | 6 | 3 |
| Rsync execution, JSON persistence, handlers | 3 | 3 | 1 |
| Views | 4 | 15 | 2 |
| App lifecycle & project configuration | 1 | 2 | 2 |
| **Total (65 reviewed findings)** | **13** | **36** | **16** |

The original report materially overstated the current Critical count: 17 of
its 28 Critical labels were downgraded or marked Not Relevant. Two originally
Non-Critical findings were upgraded because JPG export can silently omit files
or overwrite output. The remaining 13 Critical findings are credible
release-blocking correctness/integrity issues.

### Recommended closure order

1. **Protect culling persistence first.** Use `rating == nil` as the only
   unrated state; make the rating cache optional/explicit; include
   `filerecords` and `burstWinnerOverrides` in equality (or replace equality
   with a persistence generation); make corrupt JSON a distinct recoverable
   error; and await `flushPersistence()` before catalog-state replacement and
   application termination. Add tests for scored-but-unrated photos, keeper
   undo, two edits during a save, corrupt-store recovery, catalog switching
   inside the debounce window, and quit immediately after rating.

2. **Make copy/export completion truthful and collision-safe.** Enable rsync
   exit-status checking and propagate a typed failure into the copy UI. Record
   every JPG decode/encode/demosaic failure. Preflight destination names for the
   entire batch and require an explicit overwrite/rename policy. Test non-zero
   rsync exit, disk-full/permission errors, same-stem exports, and each decode
   failure branch.

3. **Give sharpness work request identity.** Track the requested file-ID set
   plus scoring signature/configuration. A different request should cancel and
   replace the old generation (or queue separately), and only its owning
   generation may publish/persist results. Test overlapping catalog and scoped
   burst requests with different sources/settings.

4. **Make actions use exactly the rendered photo set.** Derive range, badge,
   batch-rating, keyboard, and zoom navigation from the same
   `BurstGroupCleanViewPolicy.visibleFiles` result used to render. Clear/cancel
   focus masks on selection change. Give comparison image loads a per-file
   source generation and reject results whose file/source/load key is no longer
   current. Add interaction tests proving hidden frames cannot be selected or
   rated and stale pixels/masks cannot be displayed under a new file ID.

5. **Close Non-Critical findings in focused batches.** Suggested batches are:
   cache identity/eviction and cancellation; auxiliary async UI generations;
   focus metadata validation; accessibility/semantics; diagnostics/logging;
   and settings/temp-file/bookmark robustness. These should not block the four
   integrity workstreams above unless a fix naturally touches the same code.

6. **Close Not Relevant findings with conditions, not code churn.** Record the
   production invariant in a test or comment where valuable: operation actors
   are one-shot; catalogs are flat; managed AI descriptors remain blocked; the
   custom save URL is test-only; generated user-selected-file entitlement comes
   from the build setting; and current evidence producers emit unique strings.
   Reopen the conditional AI findings before any descriptor becomes `.ready`,
   and reopen basename identity before recursive or aggregated catalogs ship.

### Verification performed

- Focused `RawCullTests` suites for `CullingModelTests`,
  `SharpnessScoringTests`, and `CullingGridCoordinatorTests` built and passed.
  These tests confirm current behavior/invariants; they do not close the
  reviewed defects, and the closure plan above identifies missing regressions.
- Xcode's generated Debug entitlements were inspected after the test build and
  include `com.apple.security.files.user-selected.read-write = true` for the
  RawCull app, confirming the build-setting assessment.
- Package resolution with automatic updates disabled selected xgrammar revision
  `cee45aa95b8cdb5b16a8e11c037336870ec22369`, matching the checked-in lockfile.
- The report contains one review verdict for each of its 65 findings, and the
  final counts were checked against those verdicts.

### Definition of done

A Critical issue should be closed only when the implementation change and a
regression test both land, the relevant failure is surfaced to the user (rather
than only logged), and immediate quit/cancel/retry behavior has been exercised.
After the 13 Critical findings are fixed, regenerate this table from the issue
verdicts and move resolved entries to a dated closure section instead of
deleting the review history.
