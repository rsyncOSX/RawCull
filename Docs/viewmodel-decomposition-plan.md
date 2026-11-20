# Plan: Breaking up `RawCullViewModel`

Status: draft · 2026-11-20 · branch `version-3.4.8`

## Why

The graphify report says `RawCullViewModel` has **399 edges**, more than any other node. It connects about 65 communities, and its own community has a **cohesion score of 0.02**, so the pieces grouped with it barely relate to each other. Today it has:

- **103 stored properties** in `RawCullViewModel.swift` and about 2,500 lines including its seven extensions
- **73 app files** that reference it, **59 of them views** that take the whole object
- 6 protocol conformances, each a narrowed view of the same object

Splitting it into extensions (`+Catalog`, `+BurstGrouping`, …) only spread it across files; it's still one object. Every view still depends on all of its state, any change to it can break any feature, and SwiftUI observation can't make it clear which view depends on which state.

The codebase already shows the pattern that works: `BurstReviewSessionModel`, `CatalogLifecycleCoordinator`, `BurstAnalysisCoordinator`, `ZoomSessionModel` and `LoupeSessionModel` are each a focused `@MainActor @Observable` owner. This plan finishes that work.

## Goal and non-goals

**End state:** `RawCullViewModel` becomes a thin **workspace composition root**. It holds a `let` for each slice model, the few operations that really cut across slices (switching catalogs, switching main view mode), and the protocol conformances that need several slices. Views depend on the slice they use, injected via `.environment(...)`, not on the root.

**Targets**

| Metric | Today | Target |
|---|---|---|
| Stored properties on the root | 103 | ≤ 20, mostly `let` slice models |
| App files referencing `RawCullViewModel` | 73 | ≤ 25 |
| graphify edges on `RawCullViewModel` | 399 | ≤ 150 |
| `RawCullViewModel+BurstGrouping.swift` | 892 lines | gone (moved into its owner) |

**Non-goals:** no behaviour changes, no UI changes, no changes to `FileItem`/`RawCullFileItem`, no changes to the persistence formats. The MCP state-machine cleanup is a separate effort.

## Rules for every slice

1. **Each slice is a `@MainActor @Observable final class`, owned by the root as `let`.** SwiftUI observation works through a `let` reference: `viewModel.zoomOverlay.isVisible` registers interest only on the sub-model. That is the whole performance and coupling win.
2. **Migrate in four commits, with tests green after each:**
   1. Create the model and move the stored properties into it.
   2. Leave **temporary** forwarding computed properties on the root, the same way `burstReviewStates` and `activeBurstComparisonGroupID` forward to `burstReviewSession` today.
   3. Move call sites to the new model in batches, one feature folder at a time. Views that only need this slice switch to `@Environment(SliceModel.self)`.
   4. **Delete the forwarders.** A slice isn't done until they're gone, or the root's surface never shrinks. (The existing burst forwarders get the same treatment in Slice 7.)
3. **Signals between slices are explicit, not `didSet` side effects.** Today `files.didSet` bumps `catalogContentRevision` and clears `zoomNavigationCache`, and `ratingCache.didSet` bumps `gridContentRevision`. Each slice exposes its own `private(set) var revision: UInt64`, and anything that depends on several slices (`CullingGridProjectionKey`, `ZoomNavigationProjection`) builds its key from those revisions.
4. **Resetting on catalog change goes through one place.** Each slice gets `func resetForCatalogChange()`. The root calls them in a fixed order from what is now `resetCatalogWorkingSet()` and the catalog transition path. This replaces resets scattered across the code.
5. **Narrow protocols stay, but point at the slice.** `ImageReviewRatingProviding`, `ComparisonSessionSelection`, `MCPAnalysisWorkspace` and the others keep their shape. Their conformance moves to the slice that owns the data when one slice can satisfy it alone, and stays on the root when it needs several.
6. **The test helper is the only way tests build the view model.** `makeRawCullViewModel()` in `RawCullTests/TestIsolationHelpers.swift` stays that way. Slice tests build the slice directly with no root, which gives new, faster tests.

## Slices, in migration order

The order goes from least risk and fewest consumers to most. Each slice is one PR.

### Slice 0: Remove dead state (about 30 min)

Each of these appears only where it's declared:

- `zoomCGImageWindowFocused`, `zoomNSImageWindowFocused` (left over from the old separate zoom windows)
- `previouslySelectedFileID`

Also check `showingAlert` (3 references) and `processedURLs` (3) while doing this.

### Slice 1: `ZoomOverlayModel` (low risk, about 11 files)

**Moves:** `zoomOverlayVisible`, `zoomOverlayNavigationAxis`, `zoomOverlayNavigationContext`, `zoomOverlayLaunchContext`, `zoomOverlayNativeSize`, `zoomOverlayRAWIsReduced`, `zoomOverlayRAWRenderSeconds`, `zoomOverlayCGImage`, `zoomOverlayAnalysisCGImage`, `zoomOverlayNSImage`, `zoomExtractionTask`, `zoomContextRevision`, `open(...)`, `close()`.

**Consumers:** `ZoomOverlayView`, `ZoomOverlayControls`, `ZoomPreviewHandler`, `ZoomOverlayAnalysisCoordinator`, `ZoomNavigationPresentation`, `LoupeMainImageView`, `ThumbnailKeyNavigationModifier`, `ComparisonGridView`, `BurstCullingWorkspaceView`, `AIAssessmentWorkspace`, `RawCullMainView`.

**Coupling to handle:** `openZoomOverlay` reads `mainViewMode` to choose the axis, so pass the axis in. `selectMainViewMode` calls `closeZoomOverlay()`, which stays on the root as cross-slice orchestration. Decide whether `ZoomSessionModel` (viewport and RAW inspection) should sit *inside* `ZoomOverlayModel`; that's the natural home.

### Slice 2: Loupe viewport into `LoupeSessionModel` (low risk, 3 files)

**Moves:** `scale`, `lastScale`, `offset`, `lastOffset`, `resetZoom()`.
**Consumers:** `LoupeKeyboardController`, `LoupeMainImageView`, `LoupeImageControls`.
`LoupeSessionModel` already exists. Fold these in, or embed a `ComparisonViewportInteractionState` the way `ZoomSessionModel` does.

### Slice 3: `WorkspacePresentationModel` (low risk, many small consumers)

The window chrome and sheet/alert routing.

**Moves:** `alertType`, `alertTitle`, `alertMessage`, `activeSheet`, `sheetType`, `showCopyARWFilesView`, `isShowingPicker`, `operationFailurePresentation`, `showsLoupeMetadataPanel`, `memoryPressureWarning`, and the menu-command flags `focusAbortTask`, `focusExtractJPGs`, `focusCopyTaggedFiles`.

`alertMessage` needs `files.count`, so pass it in as a parameter instead of reading the catalog.

### Slice 4: `FileOperationsModel` (medium risk)

JPG extraction, JPG cache warming and copy progress, currently in `+Thumbnails`.

**Moves:** `extractJPGExportMode`, `extractJPGSelectedOnly`, `extractJPGDestination`, `currentExtractAndSaveJPGsActor`, `currentScanAndExtractJPGsActor`, `jpgCacheWarmTask`, `fileOperationCompleted`, `fileOperationTotal`, `fileOperationEstimatedSeconds`, `remoteDataNumbers` (32 references, so do it in its own commit), and `presentExtractJPGsSheet`, `startSelectedJPGExtraction`, `startScanAndExtractJPGs`, `abort()`, the progress handlers.

**Depends on:** reading the catalog's files and selection. Take a small `CatalogReading` protocol (defined in Slice 6, but you can add it early as a protocol on the root).

### Slice 5: `RatingsModel` (medium risk, the hot path)

Wraps `CullingModel` and owns the projection the views read.

**Moves:** `cullingModel`, `ratingCache`, `taggedNamesCache`, `ratingFilter`, and everything in `+Culling`: `getRating`, `rating(for:)`, `updateRating…`, `rebuildRatingCache`, `passesRatingFilter`, `extractRatedfilenames`, `clear…CullingState`, `retryCullingPersistence`, `archiveCullingStoreAndReset`.

**Coupling to handle:** `ratingCache.didSet` → `gridContentRevision`. Replace it with `RatingsModel.revision` and fold that into `CullingGridProjectionKey` (rule 3). `updateRatingAndAdvance` changes the selection, so give `RatingsModel` an `ImageReviewSelectionActing` reference or have the root orchestrate it. The `ImageReviewRatingProviding`/`Acting` conformances move here.

**Extra tests:** grid projection rebuilds when ratings change (`gridProjectionBuildCount` is already asserted in 9 test places, so use it).

### Slice 6: `CatalogWorkspace` + `SelectionModel` (high risk, the most-read state)

This is the heaviest-traffic state: `selectedFileID` (60 view references), `selectedSource` (52), `files` (30), `selectedFile` (29), `selectedFileIDs` (26).

**`CatalogWorkspace` moves:** `sources`, `selectedSource`, `pendingCatalogTransitionSource`, `catalogLoadFailure`, `files`, `filteredFiles`, `catalogDisplayCandidates`, `searchText`, `sortOrder`, `sortFiles`, `sortGeneration`, `isSorting`, `scanning`, `scanDiscoveredCount`, `isCreatingThumbnails`, `metadataProgress`, `thumbnailProgress`, `preloadTask`, `focusPoints`, `catalogContentRevision`, `gridContentRevision`, the projection caches, plus most of `+Catalog`: loading, sorting, `applyFilters`, `activeCatalogFiles`. It sits next to `CatalogLifecycleCoordinator`, which it can own.

**`SelectionModel` moves:** `selectedFileID`, `selectedFileIDs`, `cullingGridRenderedFileIDs`, `comparisonFileIDs`, `selectFile`, `preselectFirstVisibleFileByName`. It's split out because most narrow protocols (`ImageReviewSelectionActing`, `ComparisonSessionSelection`) need only selection.

**Coupling to handle:** `applyFilters` reads ratings, sharpness and similarity/semantic state. Inject those as read-only protocols (`RatingFilterProviding`, etc.) instead of the root. `selectedFile` becomes a lookup on `CatalogWorkspace` keyed by `SelectionModel.selectedFileID`; consider an ID→index dictionary while you're there, since it's a linear `first(where:)` today.

**Do it in two PRs:** `SelectionModel` first (smaller, used by more protocols), then `CatalogWorkspace`.

### Slice 7: `BurstWorkflowController` (high risk, the biggest win)

Turns `RawCullViewModel+BurstGrouping.swift` (892 lines) into a real owner.

**Moves:** `burstAnalysisCoordinator`, `burstReviewSession`, `burstFullReindexRequest`, `isPreparingBurstCatalog`, `burstCatalogPreparationGeneration`, `completedBurstAnalysisContext`, `showsDetailedBurstComparison`, every burst forwarder on the root, and the ~50 functions in `+BurstGrouping`: analysis start/reindex/regroup, keep best/top two, queue navigation, review states, undo, cache persistence, `deepAIReviewContext`.

**Depends on:** `CatalogWorkspace` (files, catalog URL), `SelectionModel`, `RatingsModel` (keep-best writes ratings), the sharpness and similarity models. That's why it goes last: by now all of those exist as narrow types it can take in `init`.

**The `DeepAIReviewApplicationContext` and `RawCullSimilarityApplicationContext` conformances** probably move here. Check each requirement.

### Slice 8: Shrink the root and verify

- The root holds the slices, `mainViewMode`/`selectMainViewMode`, catalog-transition orchestration, the `MCPAnalysisWorkspace` conformance (it really does span slices, which is what the doc comment on that protocol says), and `init` wiring.
- Remove any forwarders that are left.
- Move `RawCullApp` to inject each slice: `.environment(viewModel.catalog)`, `.environment(viewModel.selection)`, and so on.
- Re-run graphify and compare against the targets table.

## Risks and how to handle them

| Risk | Mitigation |
|---|---|
| Observation regressions (a view stops updating) | Forwarders in step 2 keep the old paths working while call sites move. Smoke-test each main view mode after every slice. |
| Lost revision bumps → stale grid or zoom navigation | Rule 3, plus tests asserting `gridProjectionBuildCount` / `zoomNavigationBuildCount` change exactly when they should. |
| Catalog switch leaves stale state in a slice | Rule 4. Add one test that loads catalog A, switches to B, and asserts every slice reports empty or reset state. |
| Init-order cycles (slices needing each other) | Pass dependencies as protocols in `init`. Where two slices really need each other, the root orchestrates; don't give the slices back-references to each other. |
| Merge pain on a branch that moves fast | One slice per PR, merged quickly. Don't run several slices at once in the same files. |
| MCP jobs touching state that moved | `MCPAnalysisWorkspace` is the contract. Its conformance keeps compiling throughout, and `MCPJobLifecycleTests` covers it. |

## Effort estimate

| Slice | Size | Risk |
|---|---|---|
| 0 Dead state | XS | none |
| 1 Zoom overlay | S | low |
| 2 Loupe viewport | XS | low |
| 3 Presentation | S | low |
| 4 File operations | M | medium |
| 5 Ratings | M | medium |
| 6 Selection + catalog | L (2 PRs) | high |
| 7 Burst workflow | L | high |
| 8 Root cleanup | S | low |

Slices 0–3 can land within a week and already take about 30 properties off the root. Slices 6–7 hold most of the value and most of the risk.
