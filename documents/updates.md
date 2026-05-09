# RawCull Functionality Review - Verified Completed Items

This review looked at RawCull as a RAW culling app, focusing on missing workflow functions, architecture pressure, and refactor opportunities.

Verification update: open items from this review were moved to `documents/model.md` on 2026-05-09. The items left here were verified against the current codebase as completed.

## Review Findings

### Finding 1: Source changes can leave old scan/preload work racing the new catalog (DONE, VERIFIED)

**File:** `RawCull/Views/RawCullSidebarMainView/RawCullMainView.swift`  
**Lines:** 166-175  
**Priority:** P1

The `.task(id: selectedSource)` starts an unstructured nested `Task`, so SwiftUI cancellation of the outer task does not reliably cancel the actual scan/preload work. If the user switches catalogs quickly, an older `handleSourceChange` can still assign `files`, `filteredFiles`, scoring state, or thumbnail actor state after a newer selection starts.

**Recommendation:** Store a single catalog-load task on the view model, cancel it before each new load, and check that the URL still matches before committing results.

Current state: `RawCullViewModel` owns `catalogLoadTask` and `activeCatalogLoadURL`, `startCatalogLoad(for:)` cancels the previous load before starting the next one, and `handleSourceChange(url:)` gates state commits through `isActiveCatalogLoad(_:)`.

### Finding 2: Rating writes are fire-and-forget and can persist out of order (DONE, VERIFIED)

**File:** `RawCull/Model/ViewModels/RawCullViewModel+Culling.swift`  
**Lines:** 59-132  
**Priority:** P1

Rapid keyboard culling creates independent `Task` writes. Because each task mutates shared saved state then awaits disk I/O, older writes can complete after newer ones and overwrite the JSON with stale state. This is central culling data.

**Recommendation:** Move rating mutations and persistence into a single serialized culling store/service, ideally with coalesced saves.

Current state: `RawCullViewModel+Culling` delegates rating mutations to `CullingModel`, which updates `savedFiles` on the MainActor and coalesces persistence through a cancellable delayed `saveTask`.

### Finding 4: Grid and similarity grid duplicate most of their rendering/culling logic (DONE, VERIFIED)

**File:** `RawCull/Views/GridView/GridThumbnailSelectionView.swift`  
**Lines:** 18-420  
**Priority:** P2

`GridThumbnailSelectionView` and `SimilarityGridSelectionView` both define their own burst header, selection behavior, cache key, cache recomputation, overlays, rating filter, and cell rendering. This will make culling behavior drift between modes.

**Recommendation:** Introduce a shared `CullingGridView` with pluggable header controls to remove duplicated behavior without changing the UX.

Current state: `GridThumbnailSelectionView` and `SimilarityGridSelectionView` are thin wrappers over `RawCull/Views/CullingGrid/CullingGridView.swift`, with mode-specific controls supplied through a header slot.

## Review Scope

This was a static functionality review. No code changes or test runs were performed as part of the review.
