# RawCull Functionality Review

This review looked at RawCull as a RAW culling app, focusing on missing workflow functions, architecture pressure, and refactor opportunities.

Short version: the app already has a strong core for culling, thumbnailing, sharpness scoring, focus overlays, similarity ranking, burst grouping, and rsync copy. The biggest gaps are less "missing algorithms" and more workflow polish plus a few state/refactor risks.

## Review Findings

### Finding 1: Source changes can leave old scan/preload work racing the new catalog

**File:** `RawCull/Views/RawCullSidebarMainView/RawCullMainView.swift`  
**Lines:** 166-175  
**Priority:** P1

The `.task(id: selectedSource)` starts an unstructured nested `Task`, so SwiftUI cancellation of the outer task does not reliably cancel the actual scan/preload work. If the user switches catalogs quickly, an older `handleSourceChange` can still assign `files`, `filteredFiles`, scoring state, or thumbnail actor state after a newer selection starts.

**Recommendation:** Store a single catalog-load task on the view model, cancel it before each new load, and check that the URL still matches before committing results.

### Finding 2: Rating writes are fire-and-forget and can persist out of order (DONE)

**File:** `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift`  
**Lines:** 59-132  
**Priority:** P1

Rapid keyboard culling creates independent `Task` writes. Because each task mutates shared saved state then awaits disk I/O, older writes can complete after newer ones and overwrite the JSON with stale state. This is central culling data.

**Recommendation:** Move rating mutations and persistence into a single serialized culling store/service, ideally with coalesced saves.

### Finding 3: Auto sharpness prerequisite can be bypassed by concurrent actions

**File:** `RawCull/Views/SimilarityGridView/SimilarityGridSelectionView.swift`  
**Lines:** 390-401  
**Priority:** P2

`runWithAutoScoring` assumes `scoreFiles` guards duplicate runs safely, but if a second action starts while scoring is already in progress, `scoreFiles` returns early and the action proceeds without scores. That means burst grouping can run without the intended sharpness prerequisite.

**Recommendation:** Track and await a shared scoring task, or disable analysis actions while calibration/scoring is active.

### Finding 4: Grid and similarity grid duplicate most of their rendering/culling logic  (DONE)

**File:** `RawCull/Views/GridView/GridThumbnailSelectionView.swift`  
**Lines:** 18-420  
**Priority:** P2

`GridThumbnailSelectionView` and `SimilarityGridSelectionView` both define their own burst header, selection behavior, cache key, cache recomputation, overlays, rating filter, and cell rendering. This will make culling behavior drift between modes.

**Recommendation:** Introduce a shared `CullingGridView` with pluggable header controls to remove duplicated behavior without changing the UX.

### Finding 5: Local grid rating filters are implemented but not exposed

**File:** `RawCull/Views/GridView/GridThumbnailSelectionView.swift`  
**Lines:** 82-93  
**Priority:** P3

The grid has a local `GridRatingFilter` including `unrated`, but no visible controls appear to mutate this local state. The app has global rating filters elsewhere, but the local filter code looks partly stranded.

**Recommendation:** Either expose this filter in the grid header or remove it and rely on the shared `RawCullViewModel.ratingFilter` path.

## Missing Functions

The most valuable missing workflow features to consider:

1. **Undo/redo for ratings and group actions.** Culling is fast, keyboard-driven work; accidental `X`, `P`, or "Reject All" should be reversible.
2. **Sidecar/export interoperability.** Persisting JSON is fine internally, but XMP sidecars, Finder tags, or Lightroom/Capture One compatible exports would make RawCull fit real photo workflows better.
3. **Compare mode.** A 2-up/4-up loupe for adjacent or similar burst frames would complement the existing burst grouping and sharpness scoring.
4. **"Hide rejected / show unreviewed" as first-class workflow states.** Some of this exists under rating filters, but unreviewed/review-progress feels under-modeled.
5. **Session summary/export report.** Counts by rejected/picked/starred, copy results, failed files, and score threshold actions would make batch work easier to trust.

## Refactor Priorities

1. **Catalog loading lifecycle:** Use one cancellable catalog task, with no nested unstructured task.
2. **Culling persistence:** Add a serialized `CullingStore` or actor-like service with coalesced writes.
3. **Shared grid component:** Merge flat grid and similarity grid rendering/selection/burst UI.
4. **File list pipeline:** Move filtering/sorting into a pure `FileListPipeline` so the view model, grid, keyboard navigation, and tests all use the same ordering.
5. **Test coverage:** Add tests around rating persistence order, catalog switching cancellation, burst "Keep Best", and filter/sort combinations.

## Review Scope

This was a static functionality review. No code changes or test runs were performed as part of the review.
