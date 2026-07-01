# RawCull — Deep Code Review

Date: 2026-07-01
Reviewed commit: `20557c6` (branch `main` at time of review)

## Scope

A full-codebase review across five subsystems, each reviewed independently and in depth:

1. **Actors & infrastructure** — `Actors/`, `Model/Cache/`, `Model/Handlers/`, `Model/JSON/`, `Model/ParametersRsync/`, `Model/Diagnostics/`, `Extensions/`
2. **Core ViewModels** — `RawCullViewModel` and its `+Catalog`/`+Culling`/`+Thumbnails`/`+Sharpness`/`+BurstGrouping`/`+Similarity`/`+Diagnostics` extensions, `CullingModel`, `SettingsViewModel`, `SimilarityScoringModel`, `GridThumbnailViewModel`, `MemoryViewModel`/`MemoryDiagnosticsViewModel`
3. **Sharpness/focus scoring pipeline** — `Model/ViewModels/FocusandSharpness/*`, `Kernels.ci.metal`, `SonyMakerNoteParser`/`SonyThumbnailExtractor` (in the `RawParserKit` package dependency)
4. **Grid/comparison/zoom views** — `ComparisonGridView`, `CullingGrid`, `GridView`, `SimilarityGridView`, `RatedGridView`, `ThumbnailComponents`, `ZoomViews`, `FocusPoints`, `FocusPeek`, `Histogram`
5. **App shell, settings, copy/rsync UI** — `Main/*`, `Views/CopyFiles`, `Views/Settings`, `Views/SavedFiles`, `Views/RawCullSidebarMainView`, `Views/Diagnostics`, `Views/FileViews`, `Views/OutputViews`, `Views/Progress`, `Views/Modifiers`, `Views/Tools`

This was a read-only review — no code was changed. Findings below are organized by severity: **P0** (crash/data-loss/security, fix first), **P1** (important correctness/concurrency bugs), **P2** (moderate/maintainability/performance), **P3** (minor).

## Overall health summary

RawCull is a well-structured Swift 6 codebase. The actor-per-concern architecture is applied consistently, MainActor-by-default isolation is respected in almost all call sites, JSON persistence uses atomic writes, and there's clear evidence of a prior, successful concurrency-hardening pass on the burst-grouping pipeline (generation counters, task ownership, cancellation-safe cleanup). The main risk areas found in this pass are: (a) untrusted binary data handling in the Sony MakerNote/JPEG parser used for AF points and diagnostics, (b) several places where the "stale-result protection" pattern established for burst analysis was not extended to sibling features (sort/search, similarity ranking, thumbnail/JPG extraction progress), (c) folder/bookmark and rsync include-list handling that can silently operate on the wrong files or the wrong folder, and (d) a handful of concrete UI/state bugs (grid filter desync, histogram crash path, zoom gesture desync).

---

## P0 — Critical (crash, data loss, or security)

### 1. New folder selections can silently copy to the old bookmarked folder
- **Severity:** P0
- **File(s):** `RawCull/Views/CopyFiles/OpencatalogView.swift:27-53`
- **Description:** `selecteditem` is updated before `startAccessingSecurityScopedResource()` and bookmark creation succeed. If either step fails, the old bookmark in `UserDefaults` is left in place. The copy pipeline prefers the stored bookmark over the displayed fallback path, so the UI can show the newly chosen folder while rsync still reads/writes the previously bookmarked folder — a silent wrong-destination (or wrong-source) copy.
- **Fix Plan:** Only commit the new path/UI state after security-scope access and bookmark save both succeed. If either step fails, clear the old bookmark for that key and surface an error instead of leaving mismatched UI and persisted state.

### 2. Rsync can reuse a stale or wrong include file, copying the wrong photos
- **Severity:** P0 (data safety: user-selected files vs. actually-copied files can diverge)
- **File(s):** `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:24-28, 65-71, 103-119, 229-235`
- **Description:** The include list always lives at a fixed path (`Documents/copyfilelist.txt`). If `extractTaggedfilenames()`/`extractRatedfilenames()` returns `nil`, or `writeincludefilelist` fails, the code logs and still launches rsync — meaning rsync can run against an old file list from a previous operation and copy files the user didn't intend. The fixed path also makes concurrent copy operations race with each other.
- **Fix Plan:** Treat "no file list" or "failed to write include file" as a hard failure and abort before starting rsync. Use a per-operation unique path in Application Support (not a fixed, shared Documents path), and delete it during cleanup.

### 3. `--include-from` file is unsafe for literal filenames (rsync filter injection)
- **Severity:** P0 (can broaden or narrow the copy set beyond user intent)
- **File(s):** `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift:65-71, 229-235`
- **Description:** The include file is built by joining raw filenames with newlines. rsync filter files interpret wildcard/meta characters (`*`, `?`, `[`, `]`, `!`, leading `+`/`-`/`#`, etc.), so filenames containing those characters won't be matched literally, and can unintentionally include or exclude other files.
- **Fix Plan:** Stop feeding raw filenames into `--include-from` unescaped. Either generate properly escaped rsync filter rules, or switch to a literal file-list transfer mode such as `--files-from`/`--from0` with NUL-separated entries (immune to pattern interpretation).

---

## P1 — Important (correctness / concurrency bugs)

### 4. Off-main AppKit drawing in thumbnail downscaling
- **File(s):** `RawCull/Actors/ScanAndCreateThumbnails.swift:255-277`
- **Description:** `downscale(_:to:)` uses `NSImage.lockFocus()`/`draw`/`unlockFocus()` inside a non-`@MainActor` actor. AppKit drawing is not thread-safe off the main thread; this can crash or corrupt thumbnails under concurrent batch preload.
- **Fix Plan:** Replace with a pure CoreGraphics/ImageIO (`CGContext`) downscale path that has no AppKit/main-thread dependency, or hop only the drawing step to `MainActor`.

### 5. Thumbnail/full-size disk caches never invalidate on source file replacement
- **File(s):** `RawCull/Actors/DiskCacheManager.swift:27-43`, `RawCull/Actors/FullSizeJPGDiskCache.swift:32-39`
- **Description:** Cache keys are derived only from the normalized source path (+ variant/version). If a RAW file is replaced in place at the same path, the app serves the stale cached thumbnail/JPEG indefinitely.
- **Fix Plan:** Include file identity (modification date + size, or inode/resource identifier) in the cache key or a validation check, and reject stale entries on load.

### 6. Thumbnail catalog discovery does not acquire security-scoped access
- **File(s):** `RawCull/Actors/DiscoverFiles.swift:14-32`, `RawCull/Actors/ScanAndCreateThumbnails.swift:81-91`
- **Description:** `DiscoverFiles.discoverFiles` enumerates the user-selected catalog without `startAccessingSecurityScopedResource()`, unlike `ScanFiles`. In a sandboxed build this can make thumbnail preloading silently fail while scanning still works.
- **Fix Plan:** Pair `start/stopAccessingSecurityScopedResource()` inside `DiscoverFiles`, or require/document that callers always pass an already-scoped URL.

### 7. Catalog switches can leave the previous catalog's files/state live under the new selection
- **File(s):** `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:16-29, 38-64, 107-119`
- **Description:** `startCatalogLoad`/`cancelCatalogLoad` clear selection but not `files`, `filteredFiles`, `focusPoints`, or rating caches before starting a new load. On scope-access failure or an empty new catalog, the old catalog's data can remain visible/operable.
- **Fix Plan:** Eagerly clear all catalog-scoped state at the start of a switch (and on cancellation/failure/empty-catalog paths); repopulate only after the new load succeeds.

### 8. Async sort/search requests can complete out of order and overwrite newer UI state
- **File(s):** `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:185-199`
- **Description:** `handleSortOrderChange()`/`handleSearchTextChange()` await `ScanFiles.sortFiles(...)` with no generation/cancellation check. A slower, older request can finish after a newer one and clobber `filteredFiles` with stale results.
- **Fix Plan:** Add a shared task/generation token for sort/search; cancel superseded work and ignore completions whose token is no longer current (mirror the burst-analysis pattern).

### 9. Similarity ranking has no stale-result protection
- **File(s):** `RawCull/Model/ViewModels/SimilarityScoringModel.swift:244-310`
- **Description:** `rankSimilar` launches a detached distance pass with no tracking/cancellation of prior ranking work. Rapidly changing the selected anchor can let an older ranking finish later and overwrite `anchorFileID`/`distances`/`sortBySimilarity` for the wrong image.
- **Fix Plan:** Mirror the existing indexing/grouping pattern — a ranking task + generation counter; cancel the old task and only commit if the generation still matches.

### 10. Burst undo cannot restore "unrated" state
- **File(s):** `RawCull/Model/ViewModels/BurstAnalysisModels.swift:112-115`, `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift:238-249, 378-382`
- **Description:** `captureUndo` stores prior ratings via `getRating(for:)`, which collapses "no record" to `0`. `undoLastBurstAction` writes those `0`s back via `applyRatings`, turning previously untouched files into explicit keeper/rating records rather than restoring "no record."
- **Fix Plan:** Store tri-state prior state (`nil` = no record present) and have undo delete records rather than writing `0` when the previous state was unrated.

### 11. `asyncgetsettings()` races initial JSON loading at startup
- **File(s):** `RawCull/Model/ViewModels/SettingsViewModel.swift:39-57, 314-343`
- **Description:** `loadTask` exists so callers can await initial loading, but `asyncgetsettings()` doesn't await it — actors calling this during startup can observe default settings before `settings.json` finishes loading. Already partially acknowledged in a comment in `applyStoredScoringSettings()`.
- **Fix Plan:** Have `asyncgetsettings()` `await ensureLoaded()` before returning a snapshot, so the documented cross-actor accessor is actually race-free.

### 12. Unvalidated embedded-JPEG offsets/lengths from Sony MakerNote can trigger oversized reads
- **File(s):** `RawParserKit/Sources/RawParserKit/SonyMakerNoteParser.swift:227-235, 454-516`
- **Description:** `locateJPEG`/`tagDataRange` trust tag-derived `offset`/`length` values from untrusted ARW metadata and pass them to `readEmbeddedJPEGData` without checking `offset + length <= fileSize`. A malformed/corrupted ARW can force very large reads, stalls, or memory spikes — this is untrusted binary input from camera files.
- **Fix Plan:** Validate JPEG offset/length against the actual file size before returning and again before reading; reject absurd lengths and out-of-range offsets.
- **Note:** `SonyMakerNoteParser` lives in the separate remote SPM package [`rsyncOSX/RawParserKit`](https://github.com/rsyncOSX/RawParserKit), not in this repo. This fix (and #27 below) must land in that package and be picked up via a version bump here.

### 13. Sharpness scoring samples against the Gaussian-expanded extent instead of true image bounds
- **File(s):** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:548-585, 593-650, 678-699, 878-889`
- **Description:** `buildAmplifiedLaplacian` leaves the blur-expanded `CIImage` extent intact, and `computeSharpnessAnalysis` renders/samples that expanded bitmap. Border exclusion ends up too small, and AF/saliency regions are shifted/widened relative to true photo bounds — biasing scores, especially at high ISO / larger blur radii.
- **Fix Plan:** Crop the Laplacian back to `inputImage.extent` before rendering/sampling; compute all full-frame/AF/saliency rectangles against the original extent only.

### 14. Grid rating filter is disconnected from the app-wide filter
- **File(s):** `RawCull/Views/CullingGrid/CullingGridView.swift:154, 464-478`; `RawCull/Views/GridView/GridThumbnailView.swift:54-69`; `RawCull/Views/SimilarityGridView/SimilarityGridView.swift:55-70`; `RawCull/Views/ThumbnailComponents/ThumbnailKeyNavigationModifier.swift:49-60`
- **Description:** `CullingGridView` keeps its own local `@State ratingFilter = .all` that nothing mutates, while keyboard navigation and sibling views use `viewModel.passesRatingFilter(...)`. Toolbar filter state, visible thumbnails, and keyboard/selection order can disagree.
- **Fix Plan:** Remove the local grid-only filter state; drive the grid from `viewModel.ratingFilter`/`viewModel.passesRatingFilter(...)` so rendering and navigation share one source of truth.

### 15. Command-click deselection leaves a file as the primary selection
- **File(s):** `RawCull/Views/CullingGrid/CullingGridSelectionCoordinator.swift:36-46`; `RawCull/Views/RatedGridView/RatedPhotoGridView.swift:70-80`
- **Description:** In command-toggle mode, deselecting an already-selected file removes it from `selectedFileIDs` but still leaves `selectedFileID` pointing at it, so it stays visually/behaviorally "primary" after being removed from the multi-selection.
- **Fix Plan:** When command-click removes the current primary item, retarget `selectedFileID` to another selected item, or clear it if none remain.

### 16. Comparison-view focus-point lookup collides on duplicate basenames
- **File(s):** `RawCull/Views/ComparisonGridView/ComparisonGridView.swift:224-228`; `RawCull/Views/ComparisonGridView/CandidateInspectorContext.swift:154-162`
- **Description:** Focus-point resolution matches by `file.name`/`sourceFile == file.name`. Two different files sharing a basename (e.g. from different subfolders) can show the wrong AF points, or suppress them when multiple matches exist.
- **Fix Plan:** Match focus-point data by a stable unique key (`FileItem.ID` or full URL/path), not filename alone.

### 17. Histogram initial load can crash the app
- **File(s):** `RawCull/Views/Histogram/HistogramView.swift:49-55`
- **Description:** The `.task` initial-load path calls `fatalError` if `NSImage` can't yield a `CGImage`. The `.onChange` path for the identical failure just logs and returns — an inconsistent, avoidable live crash.
- **Fix Plan:** Replace the `fatalError` with the same graceful log-and-return behavior used in `.onChange`.

### 18. Zoom buttons desync pinch-gesture state
- **File(s):** `RawCull/Views/ZoomViews/ZoomOverlayView.swift:817-823`; `RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:153-168`
- **Description:** Overlay/button zoom actions change `currentScale`/`viewModel.scale` but not `lastScale`. The next magnification gesture re-bases from stale state, causing a visible jump.
- **Fix Plan:** Update `lastScale` whenever a button-driven zoom changes the scale, matching the gesture end-state pattern used elsewhere.

### 19. Copy sheet can get stuck in "Copying…" forever on startup failure
- **File(s):** `RawCull/Views/CopyFiles/CopyFilesView.swift:70-77, 121-140`
- **Description:** `copyFilesinProgress = true` is set before rsync starts, with no failure path if launch/validation fails synchronously (e.g. bad bookmark/access failure). No completion callback fires, so the spinner never resets and the user gets no actionable error.
- **Fix Plan:** Make `startcopyfiles` return `Bool`/`Result`/throw; on startup failure, reset `copyFilesinProgress` and present an alert.

### 20. Copy completion UI has no failure state and can report errors as success
- **File(s):** `RawCull/Views/CopyFiles/CopyFilesView.swift:89-118, 142-160`
- **Description:** Every completion renders as a green "Dry run complete"/"Copy complete" panel. `CopyFilesView` never receives/checks an exit status or error, so an rsync run that exits with errors is still shown as success.
- **Fix Plan:** Add exit status/error detail to `CopyDataResult`; branch the UI into success vs. failure states, and don't render success when rsync reports failure.

### 21. Cmd-K abort is wired only in loupe mode
- **File(s):** `RawCull/Main/RawCullMainView.swift:121-127`, `RawCull/Views/FileViews/RawCullDetailContainerView.swift:22-27`, `RawCull/Views/Tools/MenuCommands.swift:17-23`
- **Description:** The menu command sets a focused `aborttask` binding globally, but the abort side effect only fires inside `AbortTaskFocusView`, which is only mounted in the loupe detail column. Cmd-K does nothing in grid/similarity/rated/comparison modes.
- **Fix Plan:** Handle `focusaborttask` at the `RawCullMainView` root via `.onChange`, mirroring the existing extract-JPG command flow, so abort works in every main view mode.

### 22. Thumbnail settings persist partially (torn autosave)
- **File(s):** `RawCull/Views/Settings/ThumbnailSizesTab.swift:64-72, 81-93, 101-109`
- **Description:** "Sharpen Zoom Preview" writes to disk immediately, but the thumbnail-size sliders and sharpening-amount slider wait for the explicit Save button. Users can leave the pane with a persisted enable flag but stale numeric values.
- **Fix Plan:** Use one persistence model for the whole tab — either autosave everything, or keep all edits in a draft and persist only from Save/Reset.

---

## P2 — Moderate (maintainability / performance)

### 23. `ThumbnailLoader` ignores the caller's requested size and freezes settings
- **File(s):** `RawCull/Actors/ThumbnailLoader.swift:25-33, 79-103`
- **Description:** `thumbnailLoader(file:targetSize:)` accepts `targetSize` but always requests `settings.thumbnailSizePreview` instead, so callers asking for a specific size don't get it. `cachedSettings` is also never invalidated, so runtime settings changes don't take effect for this singleton loader.
- **Fix Plan:** Pass `targetSize` through to `RequestThumbnail`; stop caching settings here, or add explicit invalidation when settings change.

### 24. Missing in-flight request coalescing allows duplicate thumbnail extraction
- **File(s):** `RawCull/Actors/RequestThumbnail.swift:41-131`
- **Description:** Multiple requests for the same URL can race through RAM miss → disk miss → extract with no keyed in-flight task table, causing duplicated extraction/encoding/disk writes under UI load (actor isolation prevents corruption, but not duplicated work).
- **Fix Plan:** Add an in-flight map keyed by `(url, targetSize)`, store a shared `Task`, await it for duplicate requests, and remove the entry on completion/cancellation.

### 25. Saved-files JSON is loaded synchronously on the MainActor during catalog load
- **File(s):** `RawCull/Model/ViewModels/CullingModel.swift:49-53`, `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift:122-126`
- **Description:** `cullingModel.loadSavedFiles()` does disk I/O + JSON decode synchronously on `@MainActor` mid-catalog-switch. For a large `savedfiles.json`, this can block the UI thread right after scanning completes.
- **Fix Plan:** Move read/decode off-main (detached/background task), then publish the decoded snapshot back on `MainActor`.

### 26. JPG extraction/warm-cache progress callbacks are not identity-gated
- **File(s):** `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift:62-90, 108-128, 157-176`
- **Description:** Unlike catalog preload, these handler closures write directly to shared progress fields with no check that the emitting actor/task is still current. After `abort()` or task replacement, stale callbacks can keep updating `progress`/`max`/`estimatedSeconds`.
- **Fix Plan:** Wrap handlers with an actor-identity or generation check; only the currently active job may mutate shared progress state.

### 27. Raw diagnostics can block the UI reading whole RAW files on `@MainActor`
- **File(s):** `RawCull/Model/Diagnostics/RawFileDiagnostics.swift:5-35, 117-169`; `RawCull/Model/ViewModels/RawCullViewModel+Diagnostics.swift:4-5`; `RawParserKit/Sources/RawParserKit/SonyMakerNoteParser.swift:118-124, 202-209`
- **Description:** Diagnostics runs on the main actor and calls Sony-parser slow paths that do `read(upToCount: Int.max)`. Files that miss the fast window can cause opening diagnostics to synchronously read the entire ARW and freeze the UI.
- **Fix Plan:** Move diagnostics generation off-main (`Task.detached`/actor), hopping back to `MainActor` only to publish the final log string.
- **Note:** The slow-path calls originate in the `rsyncOSX/RawParserKit` package (see #12); the RawCull-side fix (moving the call off `@MainActor`) can land independently of the upstream package fix.

### 28. Cancelling sharpness scoring doesn't stop in-flight Vision/Core Image work promptly
- **File(s):** `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift:117-128, 179-287`; `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:32-54, 174-180, 555-562`; `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+MaskGeneration.swift:903-910`
- **Description:** Cancellation is only checked between stages; `VNImageRequestHandler.perform`, `CIContext.render`, and image decode calls are synchronous, so an aborted run keeps burning CPU/GPU until the current file's current stage finishes.
- **Fix Plan:** Check cancellation before spawning more child tasks, minimize per-file render passes, and segment expensive work so cancellation cuts off sooner.

### 29. Shared thumbnail view can apply stale async results after cancellation
- **File(s):** `RawCull/Views/ThumbnailComponents/ThumbnailImageView.swift:43-49`
- **Description:** The `.task(id:)` awaits `loadThumbnail()` and assigns the result without re-checking cancellation or that the current `url`/`file` still matches the request. Rapid selection/scroll changes can let an older load overwrite the current thumbnail.
- **Fix Plan:** After the await, guard `!Task.isCancelled` and re-verify identity before assigning `thumbnailImage`.

### 30. Comparison grid launches uncancelled async refreshes that can race
- **File(s):** `RawCull/Views/ComparisonGridView/ComparisonGridView.swift:60-63, 138-141, 203-221`
- **Description:** Source toggles and focus-config changes start untracked `Task` refreshes; rapid toggling/adjusting can let an older reload/mask task finish after a newer one and overwrite `imageStates` with stale content.
- **Fix Plan:** Store per-view/per-file task handles; cancel/replace on new requests, or version requests and discard stale results.

### 31. Histogram path never reaches the last bin's full width
- **File(s):** `RawCull/Views/Histogram/HistogramPath.swift:11-27`
- **Description:** `stepX` uses `rect.width / bins.count`, but points are plotted at `index * stepX`, so the last sample lands one step short of the right edge — the chart is horizontally compressed.
- **Fix Plan:** Use `(bins.count - 1)` for line-chart spacing, or switch to explicit bar/bin-width math if bars (not a line) are intended.

### 32. Rsync details view drops all rows for small outputs
- **File(s):** `RawCull/Views/OutputViews/DetailsView.swift:90-104`
- **Description:** The table always drops `min(11, originalRecords.count)` trailing rows to strip rsync's summary footer. If rsync output has 11 or fewer lines total, the details table becomes empty even though real output exists.
- **Fix Plan:** Strip only recognized footer/stat lines by content/pattern match, rather than an unconditional trailing-row count.

---

## Recommended closure order

1. **P0s (1–3)** — folder/bookmark commit ordering and rsync include-list/filter safety. These directly risk copying the wrong files or to the wrong place; fix and add regression tests before anything else.
2. **P1 concurrency/state-leak group (7–11)** — catalog switch state leak, sort/search and similarity ranking stale-result races, burst-undo tri-state, settings-load race. These share the same "generation/identity-gated commit" pattern already proven in the burst-analysis pipeline — apply it consistently.
3. **P1 binary-safety group (12–13)** — untrusted MakerNote offset validation and the Laplacian-extent crop bug, since both affect score/AF correctness on real camera files.
4. **P1 UI-correctness group (14–22)** — grid filter desync, selection/focus-point/zoom bugs, copy status/spinner/error surfacing, Cmd-K abort scope, settings autosave — each is independent and can be fixed/tested in isolation.
5. **P2 group (23–32)** — performance/maintainability items; batch these opportunistically alongside nearby feature work.

After each group, run `make test-smoke`; after P0/P1 closure, run `make test-full`.
