# RawCull Issue Queue

Last updated: 2026-07-04

This is the living queue for the deep review findings. Completed items stay only long enough to preserve verification context; open items are ordered by expected impact if left unresolved.

## Verified Done

### P0 1-3: Copy destination/source safety and rsync literal file list
- **Status:** Done and verified in current code.
- **Commits:** `0b34922` fixed P0:1 and P0:2; `16b38d0` fixed P0:3.
- **Verification:** `OpencatalogView` now saves `selecteditem` only after security-scoped access and bookmark creation succeed, and clears stale bookmarks on failure. `ExecuteCopyFiles` now aborts startup on missing/empty file lists or include-list write failure, writes per-operation copy lists under Application Support, uses `--from0` + `--files-from`, and writes NUL-separated UTF-8 filenames. Regression coverage exists in `RawCullTests/ExecuteCopyFilesStartupTests.swift`.

### P1 13: Sharpness scoring samples true image bounds
- **Status:** Done and verified in current code.
- **Commit:** `6166443` (`P13`).
- **Verification:** `computeSharpnessAnalysis` crops the scoring Laplacian to `inputImage.extent` before deriving dimensions, rendering, and converting normalized AF/saliency regions to pixel coordinates. `buildScoringLaplacian` also crops blended output back to the primary extent.

## Recommended Queue

### 1. Issue 12 — Validate embedded-JPEG offsets/lengths from Sony MakerNote
- **Urgency:** Highest remaining risk. Treat as next.
- **Impact if ignored:** Corrupt or malicious ARW metadata can drive oversized reads, stalls, or memory spikes from untrusted binary input.
- **Files:** External `rsyncOSX/RawParserKit` package, then update the RawCull package pin.
- **Recommendation:** Fix upstream first: validate `offset`, `length`, and `offset + length` against file size before returning or reading embedded JPEG data; reject absurd lengths.

### 2. Issue 4 — Off-main AppKit drawing in thumbnail downscaling
- **Urgency:** High.
- **Impact if ignored:** Concurrent thumbnail preload can crash or corrupt output because `NSImage.lockFocus()` drawing is used off the main thread.
- **Files:** `RawCull/Actors/ScanAndCreateThumbnails.swift`
- **Recommendation:** Replace AppKit drawing with a CoreGraphics/ImageIO downscale path. Prefer this over hopping to `MainActor`, because thumbnail preloading is intentionally background work.

### 3. Issue 7 — Catalog switches can leave stale catalog state visible
- **Urgency:** High.
- **Impact if ignored:** After a failed, cancelled, or empty catalog switch, users can still see or operate on files from the previous catalog.
- **Files:** `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift`
- **Recommendation:** Clear all catalog-scoped state at switch start and on failure/cancel/empty paths, then repopulate only after the new load succeeds.

### 4. Issue 20 — Copy completion UI can report rsync failures as success
- **Urgency:** High.
- **Impact if ignored:** A failed copy can be presented as a green success state, which undermines user trust and can hide missing files.
- **Files:** `RawCull/Views/CopyFiles/CopyFilesView.swift`, `CopyDataResult` model / rsync result plumbing.
- **Recommendation:** Add exit status/error detail to the copy result and render explicit success/failure states.

### 5. Issue 19 — Copy sheet can get stuck in "Copying..." on startup failure
- **Urgency:** High, and best fixed with issue 20.
- **Impact if ignored:** Startup validation failures can leave the sheet spinning with no actionable error.
- **Files:** `RawCull/Views/CopyFiles/CopyFilesView.swift`, `RawCull/Model/ParametersRsync/ExecuteCopyFiles.swift`
- **Recommendation:** Make `startcopyfiles` return `Result`/throw, reset progress on startup failure, and show the failure reason.

### 6. Issue 6 — Thumbnail discovery does not acquire security-scoped access
- **Urgency:** High for sandboxed builds.
- **Impact if ignored:** Thumbnail preloading can silently fail while scanning still works.
- **Files:** `RawCull/Actors/DiscoverFiles.swift`, `RawCull/Actors/ScanAndCreateThumbnails.swift`
- **Recommendation:** Pair `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` inside discovery, or enforce an already-scoped caller contract.

### 7. Issue 5 — Disk caches never invalidate on source file replacement
- **Urgency:** Medium-high.
- **Impact if ignored:** Replacing a RAW file in place can keep stale thumbnails or full-size JPEGs indefinitely.
- **Files:** `RawCull/Actors/DiskCacheManager.swift`, `RawCull/Actors/FullSizeJPGDiskCache.swift`
- **Recommendation:** Include file identity such as modification date and size in cache validation or key derivation.

### 8. Issue 8 — Async sort/search can overwrite newer UI state
- **Urgency:** Medium-high.
- **Impact if ignored:** Slower old sort/search tasks can clobber newer filtered results.
- **Files:** `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift`
- **Recommendation:** Add a shared generation token or task cancellation pattern matching the burst-analysis pipeline.

### 9. Issue 9 — Similarity ranking has no stale-result protection
- **Urgency:** Medium-high.
- **Impact if ignored:** Rapid anchor changes can show ranking results for the wrong image.
- **Files:** `RawCull/Model/ViewModels/SimilarityScoringModel.swift`
- **Recommendation:** Add ranking task ownership plus generation-gated commits for `anchorFileID`, `distances`, and `sortBySimilarity`.

### 10. Issue 10 — Burst undo cannot restore "unrated" state
- **Urgency:** Medium-high.
- **Impact if ignored:** Undo can turn previously untouched files into explicit `0` rating records.
- **Files:** `RawCull/Model/ViewModels/BurstAnalysisModels.swift`, `RawCull/Model/ViewModels/RawCullViewModel+BurstGrouping.swift`
- **Recommendation:** Store prior rating as tri-state: no record, explicit zero, or positive rating. Delete records on undo when prior state was no record.

### 11. Issue 11 — `asyncgetsettings()` races initial JSON loading
- **Urgency:** Medium.
- **Impact if ignored:** Startup actors can observe defaults before saved settings finish loading.
- **Files:** `RawCull/Model/ViewModels/SettingsViewModel.swift`
- **Recommendation:** Await `ensureLoaded()` inside `asyncgetsettings()` before returning the snapshot.

### 12. Issue 14 — Grid rating filter is disconnected from app-wide filter
- **Urgency:** Medium.
- **Impact if ignored:** Visible thumbnails and keyboard selection/navigation can disagree with toolbar filter state.
- **Files:** `RawCull/Views/CullingGrid/CullingGridView.swift`, `RawCull/Views/GridView/GridThumbnailView.swift`, `RawCull/Views/SimilarityGridView/SimilarityGridView.swift`, `RawCull/Views/ThumbnailComponents/ThumbnailKeyNavigationModifier.swift`
- **Recommendation:** Remove local grid-only rating state and drive all filtering from `viewModel.ratingFilter` / `passesRatingFilter`.

### 13. Issue 15 — Command-click deselection leaves stale primary selection
- **Urgency:** Medium.
- **Impact if ignored:** A deselected file can remain the primary visual/behavioral selection.
- **Files:** `RawCull/Views/CullingGrid/CullingGridSelectionCoordinator.swift`, `RawCull/Views/RatedGridView/RatedPhotoGridView.swift`
- **Recommendation:** When removing the current primary item, retarget to another selected item or clear primary selection.

### 14. Issue 16 — Comparison focus-point lookup collides on duplicate basenames
- **Urgency:** Medium.
- **Impact if ignored:** Comparison views can display wrong AF points when different folders contain files with the same name.
- **Files:** `RawCull/Views/ComparisonGridView/ComparisonGridView.swift`, `RawCull/Views/ComparisonGridView/CandidateInspectorContext.swift`
- **Recommendation:** Match focus-point data by stable file identity or full URL/path, not basename.

### 15. Issue 17 — Histogram initial load can crash
- **Urgency:** Medium, quick fix.
- **Impact if ignored:** A bad image conversion path can crash the app during initial histogram load.
- **Files:** `RawCull/Views/Histogram/HistogramView.swift`
- **Recommendation:** Replace `fatalError` with the existing graceful log-and-return behavior used by the change handler.

### 16. Issue 18 — Zoom buttons desync pinch gesture state
- **Urgency:** Medium.
- **Impact if ignored:** The next pinch after button zoom can jump because `lastScale` is stale.
- **Files:** `RawCull/Views/ZoomViews/ZoomOverlayView.swift`, `RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift`
- **Recommendation:** Update `lastScale` whenever button-driven zoom changes scale.

### 17. Issue 21 — Cmd-K abort only works in loupe mode
- **Urgency:** Medium.
- **Impact if ignored:** Abort command appears global but does nothing in grid/similarity/rated/comparison modes.
- **Files:** `RawCull/Main/RawCullMainView.swift`, `RawCull/Views/FileViews/RawCullDetailContainerView.swift`, `RawCull/Views/Tools/MenuCommands.swift`
- **Recommendation:** Handle the focused abort binding at the `RawCullMainView` root and avoid double-handling in loupe.

### 18. Issue 22 — Thumbnail settings persist partially
- **Urgency:** Low-medium.
- **Impact if ignored:** Users can persist the enable flag without matching slider values.
- **Files:** `RawCull/Views/Settings/ThumbnailSizesTab.swift`
- **Recommendation:** Use one persistence model for the whole tab: all autosave, or all draft-until-save.

### 19. Issue 23 — `ThumbnailLoader` ignores requested size and freezes settings
- **Urgency:** Low-medium.
- **Impact if ignored:** Callers requesting a size may get the preview setting instead, and runtime setting changes may not take effect.
- **Files:** `RawCull/Actors/ThumbnailLoader.swift`
- **Recommendation:** Pass `targetSize` through and invalidate or remove cached settings.

### 20. Issue 24 — Missing in-flight request coalescing duplicates thumbnail work
- **Urgency:** Low-medium.
- **Impact if ignored:** UI load can duplicate extraction, encoding, and disk writes for the same thumbnail.
- **Files:** `RawCull/Actors/RequestThumbnail.swift`
- **Recommendation:** Add an actor-owned in-flight task map keyed by URL and target size.

### 21. Issue 25 — Saved-files JSON loads synchronously on MainActor
- **Urgency:** Low-medium.
- **Impact if ignored:** Large saved state can block the UI during catalog load.
- **Files:** `RawCull/Model/ViewModels/CullingModel.swift`, `RawCull/Model/ViewModels/RawCullViewModel+Catalog.swift`
- **Recommendation:** Decode off-main, then publish the snapshot on `MainActor`.

### 22. Issue 26 — JPG extraction/warm-cache progress callbacks are not identity-gated
- **Urgency:** Low-medium.
- **Impact if ignored:** Cancelled or replaced jobs can keep mutating shared progress state.
- **Files:** `RawCull/Model/ViewModels/RawCullViewModel+Thumbnails.swift`
- **Recommendation:** Gate callbacks with actor identity or generation checks.

### 23. Issue 27 — Raw diagnostics can block UI reading whole RAW files
- **Urgency:** Low-medium.
- **Impact if ignored:** Diagnostics can freeze the UI while slow parser paths read large files.
- **Files:** `RawCull/Model/Diagnostics/RawFileDiagnostics.swift`, `RawCull/Model/ViewModels/RawCullViewModel+Diagnostics.swift`, plus upstream RawParserKit slow-path work.
- **Recommendation:** Move local diagnostics generation off-main; handle upstream full-file read behavior with issue 12.

### 24. Issue 28 — Sharpness cancellation does not stop in-flight Vision/Core Image work promptly
- **Urgency:** Low-medium unless users frequently abort scoring batches.
- **Impact if ignored:** Aborted scoring runs can keep burning CPU/GPU until the current synchronous stage finishes.
- **Files:** `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift`, `FocusMaskEngine+Scoring.swift`, `FocusMaskEngine+MaskGeneration.swift`
- **Recommendation:** Add cancellation checks before spawning child work and between smaller expensive stages; avoid changing scoring output while refactoring.

### 25. Issue 29 — Shared thumbnail view can apply stale async results
- **Urgency:** Low-medium, quick fix.
- **Impact if ignored:** Rapid scrolling or selection changes can show a stale thumbnail.
- **Files:** `RawCull/Views/ThumbnailComponents/ThumbnailImageView.swift`
- **Recommendation:** After await, guard cancellation and verify request identity before assignment.

### 26. Issue 30 — Comparison grid refreshes can race
- **Urgency:** Low-medium.
- **Impact if ignored:** Rapid source/focus toggles can leave stale image states visible.
- **Files:** `RawCull/Views/ComparisonGridView/ComparisonGridView.swift`
- **Recommendation:** Store cancellable task handles or request versions and discard stale completions.

### 27. Issue 31 — Histogram path does not reach last bin's full width
- **Urgency:** Low.
- **Impact if ignored:** Histogram line is horizontally compressed.
- **Files:** `RawCull/Views/Histogram/HistogramPath.swift`
- **Recommendation:** Use `bins.count - 1` spacing for line charts or explicit bin-width math for bars.

### 28. Issue 32 — Rsync details view drops all rows for small outputs
- **Urgency:** Low.
- **Impact if ignored:** Small rsync outputs can render as an empty details table.
- **Files:** `RawCull/Views/OutputViews/DetailsView.swift`
- **Recommendation:** Strip recognized footer/stat lines by content instead of dropping a fixed number of trailing rows.

## Test Policy

- Run focused tests for each issue where practical.
- Run `make test-smoke` after each queue item or tightly related batch.
- Run `make test-full` after closing the remaining high-impact P1 queue, especially issues 4, 7, 12, 19, and 20.
