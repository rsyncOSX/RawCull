# RawCull Code Review — Issues

This document reports findings from a static, read-only deep review of the
RawCull codebase (`RawCull/`, `RawCullModelDownloader/`, project/build
configuration, and Swift package pinning). **No build, test, or lint tooling
was run** — every finding below is based on reading the source directly.
Line numbers refer to the reviewed revision on this branch and may drift as
the code changes.

Each issue lists a **Severity**:

- **Critical** — can cause a crash, data loss/corruption, a security/integrity
  gap, or user-visible incorrect behavior in a core workflow (ratings,
  culling, copying files, image identity).
- **Non-Critical** — a code smell, inefficiency, minor UX/accessibility rough
  edge, or a real but low-probability edge case.

## Summary

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

---

## 0. Cross-cutting: rating state conflates "never rated" with "explicitly kept" (Critical)

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
**Issue:** `downscale(_:to:)` calls `NSImage.lockFocus()`, `draw(in:)`, and
`unlockFocus()` from a non-`@MainActor` actor.
**Justification:** AppKit's `NSImage` drawing APIs are not documented as
thread-safe; performing them concurrently off the main actor risks corrupted
bitmaps or crashes under concurrent thumbnail generation.

### RawCull/Actors/ScanAndExtractJPGs.swift:39-82,84-150
**Title:** Cancelled JPG warmups can corrupt the next warmup run
**Severity:** Critical
**Issue:** Same cancel-then-immediately-reuse-state pattern as the two issues
above: `cancelExtraction()` cancels and clears `extractTask`, but
`extractCatalogJPGs()` resets counters while the old task's children may still
be running.
**Justification:** Late completions from a superseded warmup can still mutate
the new run's counters/timing, producing incorrect progress/ETA.

### RawCull/Actors/SharedMemoryCache.swift:121-125,388-425
**Title:** `nonisolated(unsafe)` cache APIs bypass actor/sendability safety for `NSImage`
**Severity:** Critical
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
**Issue:** The cache key hashes only `standardized.path` + `variant`, unlike
`ThumbnailCacheKey`, which also incorporates file size and modification date.
**Justification:** Replacing a RAW file in place (same path, new bytes) can
return a stale cached full-size JPEG for the new file.

### RawCull/Actors/SaveJPGImage.swift:51-68
**Title:** Export filenames collide on duplicate basenames
**Severity:** Critical
**Issue:** `outputURL(...)` derives the destination filename only from
`lastPathComponent` (plus a `_demosaic` suffix), dropping the source
directory, and writes atomically with no collision detection.
**Justification:** Two source RAW files with the same basename from different
folders (a common occurrence across multiple card imports/subfolders) silently
overwrite each other's exported JPEG.

### RawCull/Actors/ThumbnailLoader.swift:81-112
**Title:** Requested thumbnail size is ignored after slot acquisition
**Severity:** Non-Critical
**Issue:** Outside the small (`<= 200`) fast path, the loader always requests
`settings.thumbnailSizePreview` from `RequestThumbnail`, ignoring the caller's
`targetSize`.
**Justification:** Callers requesting a specific size can get back a
differently-sized image, which can also poison size-keyed caches with the
wrong dimensions.

### RawCull/Actors/DiscoverFiles.swift:14-32
**Title:** Detached scan ignores cancellation
**Severity:** Non-Critical
**Issue:** Directory discovery is launched with `Task.detached` (which does
not inherit the caller's cancellation) and the enumeration loop never checks
`Task.isCancelled`.
**Justification:** A cancelled scan/preload keeps enumerating the file system
and doing wasted work after its result is no longer needed.

### RawCull/Actors/DiskCacheManager.swift:89-101,153-178
**Title:** Thumbnail disk cache has no size cap
**Severity:** Non-Critical
**Issue:** Every save persists a new JPEG; the only cleanup path is an
externally-triggered, age-based prune (`pruneCache(maxAgeInDays:)`).
**Justification:** Without a size-based eviction policy, long-running use on
large catalogs can grow the on-disk cache unbounded between prunes.

### RawCull/Actors/ExtractAndSaveJPGs.swift:129-146,158-166
**Title:** Decode failures vanish from the export result
**Severity:** Non-Critical
**Issue:** Several failure paths (`guard let` / `try?` on embedded-preview
extraction, JPEG encoding, RAW demosaic) return early without recording a
`JPGExportFailure`.
**Justification:** Failed files can disappear from both `succeeded` and
`failures`, so the export summary under-reports how many files actually
failed.

### RawCull/Actors/ScanFiles.swift:60-105
**Title:** Directory scan fans out one metadata task per file with no throttle
**Severity:** Non-Critical
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
**Issue:** `snapshot()` reports `.installed` as soon as a pack is found
locally; the licence-acceptance check only runs on the fresh-download path.
**Justification:** A model restored from backup or preseeded outside of
`download()` can become usable without ever passing through the licence
gate, so the gate only protects one of the paths that lead to model use.

### RawCull/Model/AIIntegration/RawCullAIModelDownloadService.swift:156-175
**Title:** Download progress updates race with final completion state
**Severity:** Non-Critical
**Issue:** A separate `progressTask` streams `.downloading` updates while the
main path later calls `progress(1)`; the updater is only cancelled in
`defer`.
**Justification:** Buffered progress events can arrive after the explicit
completion callback, so the UI can flicker back to a stale "downloading"
state after already showing "installed"/"validating".

### RawCull/Model/AIIntegration/RawCullAIModelResourceManager.swift:49-53,83-165
**Title:** Model validation cache can miss metadata-preserving tampering
**Severity:** Non-Critical
**Issue:** The validation cache keys on path, kind, size, modification date,
and resolved symlink target — never file content hashes.
**Justification:** In-place file changes that preserve size and mtime reuse
the cached validation result, so a corrupted/modified model bundle can be
treated as still-valid without re-validation.

### RawCull/Model/AIIntegration/DeepAIReviewFeature.swift:680-690,797-799
**Title:** Duplicate candidate IDs can crash progress construction
**Severity:** Non-Critical
**Issue:** `progress()` builds `Dictionary(uniqueKeysWithValues: completed.map { ($0.fileID, $0) })`
without deduplicating `fileID`s first.
**Justification:** `Dictionary(uniqueKeysWithValues:)` traps on duplicate
keys; if burst assembly upstream ever produces the same `fileID` twice for a
Deep Review batch, this crashes instead of degrading gracefully.

### RawCull/Model/AIIntegration/RawCullAIModels.swift:258-297
**Title:** Saved-burst cache scan swallows per-file decode failures
**Severity:** Non-Critical
**Issue:** Non-cancellation errors while reading/decoding a cached JSON
artifact only increment a `skippedCacheFileCount`; the filename and error are
discarded.
**Justification:** Corrupt or schema-incompatible cache files become an
opaque count with no way to diagnose which file or what went wrong.

### RawCull/Model/Cache/ThumbnailCacheKey.swift:8-48,143-155
**Title:** Thumbnail keys can collide after in-place source replacement
**Severity:** Non-Critical
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
**Issue:** `scoreFiles(_:)` awaits any existing `_scoringTask` and returns
without checking whether that in-flight task was started for the same file
set, scoring source, or configuration.
**Justification:** A second scoring request issued while another is running
never launches its own work; it silently receives results from the previous,
differently-scoped batch, which then drives ranking and persistence.

### RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:131-139
**Title:** Catalog reload can clobber unsaved culling changes
**Severity:** Critical
**Issue:** Every successful catalog load calls `cullingModel.loadSavedFiles()`,
which replaces the entire in-memory culling store from disk — even if a
debounced write from a recent rating/override edit is still pending.
**Justification:** Reloading from disk can reintroduce stale state before a
pending write completes; a subsequent save built from that stale state can
overwrite a just-made edit.

### RawCull/Model/ViewModels/FocusandSharpness/FocusPointsModel.swift:45-52
**Title:** Malformed focus metadata can produce NaN/∞ coordinates
**Severity:** Non-Critical
**Issue:** `normalizedX`/`normalizedY` divide by `sensorWidth`/`sensorHeight`
without checking they are non-zero.
**Justification:** A malformed/partial EXIF AF-location string can yield zero
sensor dimensions, producing invalid coordinates that propagate into focus
overlays and downstream scoring.

### RawCull/Model/ViewModels/MemoryDiagnosticsViewModel.swift:82-83,100-109,198
**Title:** Diagnostics sampling log grows without any bound
**Severity:** Non-Critical
**Issue:** A new `Entry` is appended roughly every 5 seconds for as long as
logging is active; `entries` is never trimmed.
**Justification:** Long diagnostic sessions grow this array unboundedly,
which is a poor look specifically for a *memory* diagnostics tool.

### RawCull/Model/ViewModels/RawCullAISettingsModel.swift:225-237
**Title:** Cancelled model removal leaves the UI stuck in "removing" state
**Severity:** Non-Critical
**Issue:** `removeManagedModel(_:)` sets `.removing` before awaiting
`coordinator.remove(id)`; a `CancellationError` returns early without
restoring prior state.
**Justification:** The row can stay stuck showing "removing" with actions
disabled until an unrelated refresh happens to repair it.

### RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:93-97 (and `RawCullViewModel.getFocusPoints()`)
**Title:** Multiple AF points for one file are dropped
**Severity:** Non-Critical
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
**Issue:** `presentRawDiagnostics(for:)` launches an untracked `Task` and
unconditionally assigns `rawDiagnosticsPresentation` on completion.
**Justification:** There is no cancellation token or "is this still the
selected file" recheck, so a slower earlier request can overwrite a later
one and show diagnostics for the wrong file.

### RawCull/Model/ViewModels/SettingsViewModel.swift:194-243
**Title:** Concurrent settings saves can overwrite newer values
**Severity:** Non-Critical
**Issue:** `saveSettings()` snapshots properties and writes them from a
detached background task with no serialization against overlapping saves.
**Justification:** If two saves overlap, an older detached write finishing
after a newer one can put stale configuration back on disk.

### RawCull/Model/ViewModels/SimilarityScoringModel.swift:1247-1275
**Title:** Burst grouping silently drops files missing similarity artifacts
**Severity:** Non-Critical
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
**Issue:** A JSON decode failure is logged and the function returns `nil` —
the same value returned when the file simply doesn't exist yet.
**Justification:** Callers cannot distinguish "file is corrupt/schema
mismatch" from "no saved data ever existed." The app continues with an empty
in-memory store and can later overwrite the still-corrupt-but-recoverable
file, permanently losing previously saved ratings/overrides.

### RawCull/Model/JSON/SavedFiles.swift:87-96
**Title:** Equality/hashing ignore the actual persisted records
**Severity:** Critical
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
**Issue:** `cleanup()` removes the generated `copyfilelist-*.list0` file with
`try?` and clears `includeListURL` regardless of success.
**Justification:** If deletion fails, a file listing selected photo names is
left behind in Application Support with no remaining in-app reference to it
— an invisible, unrecoverable leak.

### RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:345-360
**Title:** Stale security-scoped bookmarks are never renewed
**Severity:** Non-Critical
**Issue:** `bookmarkDataIsStale` is captured during resolution but never
acted on.
**Justification:** Stale bookmarks should be regenerated and re-persisted;
continuing to use one can work temporarily and then start failing
intermittently across later launches or after system/volume changes.

### RawCull/Model/JSON/WriteSavedFilesJSON.swift:29-35
**Title:** Custom save URLs bypass actor serialization
**Severity:** Non-Critical
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
**Issue:** `onZoomOut`/`onZoomIn` mutate `viewModel.scale` directly but never
update `viewModel.lastScale`, while `MagnifyGesture().onChanged` computes
`scale = lastScale * value.magnification`.
**Justification:** Verified: after zooming with the toolbar +/- buttons, the
next pinch gesture starts from the stale pre-button `lastScale` and the image
snaps to an unexpected size — a visible, reproducible interaction bug.

### RawCull/Views/ZoomViews/ZoomOverlayView.swift:719-739,845-850
**Title:** Button/keyboard zoom leave gesture state out of sync
**Severity:** Critical
**Issue:** Same pattern as above: the overlay's zoom helpers change
`currentScale` without updating `lastScale`, which the pinch gesture uses as
its baseline.
**Justification:** Zooming via toolbar or keyboard shortcuts causes the next
pinch gesture to snap to an unexpected scale.

### RawCull/Views/ZoomViews/ZoomOverlayView.swift:410-420,821-825
**Title:** Stale focus mask can remain over a newly-selected photo
**Severity:** Critical
**Issue:** Navigating to another image reloads the preview and resets
zoom/source state, but does not clear `focusMask` first.
**Justification:** The previous image's focus-mask overlay can remain
visible on top of the newly-loaded photo until the delayed mask
regeneration completes, visibly misattributing focus evidence to the wrong
image.

### RawCull/Views/ZoomViews/ImageSourceToggleView.swift:26-34
**Title:** RAW-unavailable fallback can get stuck on an unusable source
**Severity:** Critical
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
**Issue:** `.task(id:)` keeps the previous thumbnail in state, awaits
`loadThumbnail()`, and unconditionally writes the result back with no
cancellation check and no clearing of old state first.
**Justification:** A slow load for a previous selection can complete after
a newer selection has already started loading, repainting the view with the
wrong photo's thumbnail.

### RawCull/Views/ThumbnailComponents/FileTableRowView.swift:109-113
**Title:** Search updates can race and overwrite newer results
**Severity:** Critical
**Issue:** Every keystroke starts a fresh, untracked `Task` calling
`handleSearchTextChange()` with no cancellation of the previous search task.
**Justification:** An older, slower text search can finish after a newer one
and overwrite `filteredFiles`, leaving the table showing results for a query
the user already changed away from.

### RawCull/Views/ComparisonGridView/ComparisonGridView.swift:59-63,202-220
**Title:** Source-toggle / bulk-load reloads can publish stale images
**Severity:** Critical
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
**Issue:** The thumbnail-loading task only assigns `nsImage` on success and
never clears it first when the selected file changes or the load fails.
**Justification:** `HistogramView` keeps rendering the previous file's
histogram — a form of misleading analysis data — until a new thumbnail
successfully arrives.

### RawCull/Views/ComparisonGridView/ComparisonImageLoader.swift:24-34
**Title:** Thumbnail sharpening ignores parent-task cancellation
**Severity:** Non-Critical
**Issue:** Sharpening runs via `Task.detached`, immediately awaited; detached
tasks do not inherit the parent's cancellation.
**Justification:** Leaving the comparison view or changing selection
mid-sharpen leaves the detached work running and burning CPU/I/O for a
result that will be discarded.

### RawCull/Views/CandidateInspectorView.swift:130-145,203-207 *(`RawCull/Views/ComparisonGridView/CandidateInspectorView.swift`)*
**Title:** Duplicate evidence strings can disappear from the inspector
**Severity:** Non-Critical
**Issue:** Reason/caution lists render with `ForEach(items, id: \.self)` over
raw, non-deduplicated `[String]`.
**Justification:** Repeated strings produce duplicate SwiftUI identities,
which can cause rows to be collapsed/reused incorrectly and hide real
evidence lines from the reviewer.

### RawCull/Views/Modifiers/ButtonStyles.swift:134-144
**Title:** Pressed-state animation has overlapping, uncancelled reset timers
**Severity:** Non-Critical
**Issue:** Every button release spawns a new sleep-then-reset `Task` without
cancelling earlier ones.
**Justification:** Rapid repeated clicks create competing timers where an
older task can end a newer press's hold-animation window early, producing
visibly jittery feedback.

### RawCull/Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:37-50,146-148
**Title:** Filtered-empty state reports the catalog itself as empty
**Severity:** Non-Critical
**Issue:** The "No Files Found" branch is driven by `viewModel.filteredFiles.isEmpty`,
not the unfiltered catalog contents.
**Justification:** If active rating/search/semantic filters simply match
nothing, the UI incorrectly tells the user the folder has no RAW images at
all and suggests picking a different catalog.

### RawCull/Views/RawCullSidebarMainView/SidebarARWCatalogFileView.swift:135-143
**Title:** Stored scan-progress closure is never cleared
**Severity:** Non-Critical
**Issue:** The view assigns a closure to `viewModel.countingScannedFiles`
that captures this view's `@State`, with no matching cleanup on disappear.
**Justification:** The callback can outlive the view and continue targeting
now-stale state, or hold a reference longer than necessary.

### RawCull/Views/SimilarityGridView/SimilarityGridSelectionView.swift:15,77-85
**Title:** Debounced regroup task survives view removal
**Severity:** Non-Critical
**Issue:** Regrouping is deferred into an unstructured `Task` that is only
cancelled when a *newer* regroup is scheduled, not when the view disappears.
**Justification:** Leaving the similarity screen inside the debounce window
can still trigger `viewModel.reGroupBursts()` from an inactive screen.

### RawCull/Views/ThumbnailComponents/FileTableRowView.swift:67-76
**Title:** Rejected and keeper ratings render identically to unrated rows
**Severity:** Non-Critical
**Issue:** The table's rating column only draws filled stars for values 2-5;
rejected (`-1`) and keeper (`0`) both fall through to the same empty-star
display as a truly unrated row.
**Justification:** The table view hides real, meaningful state
(rejected vs. kept vs. unrated) from the user at a glance.

### RawCull/Views/Settings/SettingsResetSaveButtons.swift:68-73
**Title:** "Save" action is styled as destructive
**Severity:** Non-Critical
**Issue:** `Button("Save", role: .destructive, ...)` applies destructive
role/styling to a normal save action.
**Justification:** Misleading visual and accessibility semantics for a
routine, non-destructive action.

### RawCull/Views/ThumbnailComponents/RatingFilterButtons.swift:27-36
**Title:** Color-only filter buttons lack accessible names
**Severity:** Non-Critical
**Issue:** The rejected/star filter controls are plain colored `Circle()`
views with only a `.help(...)` tooltip, no accessibility label/trait.
**Justification:** VoiceOver cannot reliably announce what each button
filters by, making this control unusable for assistive-technology users.

### RawCull/Views/Tools/MenuCommands.swift:12-23
**Title:** "Actions" menu items stay enabled with no focused target
**Severity:** Non-Critical
**Issue:** Commands rely on `@FocusedBinding` but are never disabled when no
window publishes those focused values.
**Justification:** Menu items that visually appear actionable can silently
no-op in windows that don't wire up the corresponding focused value.

---

## 6. App Lifecycle & Project Configuration

### RawCull/Main/RawCullApp.swift:57-73,108-111
**Title:** Closing the main window can quit the app without flushing pending culling saves
**Severity:** Critical
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
**Issue:** `Task.sleep(seconds:)` computes
`UInt64(seconds * 1_000_000_000)`, which traps if `seconds` is negative. A
repo-wide search found this helper has no call sites at all.
**Justification:** Dead code; low risk today since it's unused, but it's a
crash trap waiting for the first caller that passes a computed/negative
duration, and should either be removed or hardened (e.g. `max(0, seconds)`).

### RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
**Title:** `xgrammar` dependency is pinned to a moving branch, not a version/commit
**Severity:** Non-Critical
**Issue:** Every other resolved package pins a semantic version or a fixed
commit SHA; `xgrammar` (`https://github.com/mlc-ai/xgrammar`) is pinned to
`branch: main`.
**Justification:** Resolving packages fresh (or running `swift package
update`) can silently pull in new, unreviewed upstream code on `main` with no
version boundary — a reproducibility and supply-chain hygiene gap compared to
every other dependency in the project.

