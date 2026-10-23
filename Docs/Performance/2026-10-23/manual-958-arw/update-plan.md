# Prepared update plan — 958-ARW baseline

Status: source inspected; baseline saved; implementation and validation remain pending. This preparation changes documentation only. See `report.md` for evidence and limitations.

## Change 1 — remove sorting from sharpness control presentation

Files: `RawCull/Model/ViewModels/RawCullViewModel+Sharpness.swift`, `RawCull/Views/GridView/SharpnessControlsView.swift`.

1. Introduce a lightweight target count/availability calculation that follows the existing selection, star-rating and active-catalog scope rules without ordering files.
2. Have button availability and tooltip use the count. Avoid materializing ordered target arrays in view-body evaluation.
3. Retain `sharpnessScoringTargetFiles` for the scoring action. Move filename sorting into branches that require it; visible selected/rated order must remain authoritative.
4. Prefer this bounded calculation over a new cache: it removes sorting without introducing invalidation complexity. Only add stored projections if follow-up evidence justifies them.

Correctness coverage: extend `RawCullViewModelCullingTests` to ensure count, empty-state availability and descriptions agree with actual targets for empty catalog, visible and hidden selections, missing selected IDs, star filters with empty visible fallback, non-star filters, and semantic-search scope. Reuse existing target-order and scoring-persistence tests; include `RawCullSemanticSearchTests` scope coverage. Avoid wall-clock unit-test thresholds.

Done when control reads perform no localized filename sort, target identities/order are preserved, and focused tests pass.

## Change 2 — reuse zoom navigation ordering

Files: `RawCull/Model/ZoomNavigationPresentation.swift`, relevant ownership in `RawCull/Model/ViewModels/RawCullViewModel.swift`, call sites in `RawCull/Views/ZoomViews/ZoomOverlayView.swift` and `ZoomOverlayChrome.swift` as needed.

1. Inspect all readers before choosing projection ownership. Existing `gridContentRevision` and grid-projection caching provide a pattern, but grid revision alone is insufficient for every zoom input.
2. Define an immutable navigation projection containing ordered files and ID-to-index lookup. Keep selected-file index lookup separate from ordered-file construction.
3. Reuse it across next/previous checks and actions, and across selection-only changes. Avoid a dictionary/sort on each accessor or body evaluation.
4. Explicitly cover invalidation for catalog replacement, filtered files/order, contextual IDs, ratings, sharpness/similarity order mode, and metadata changes to FileItem values. Preserve contextual-ID filtering and current empty-context fallback behavior.
5. Read observable inputs before any ignored cache hit, or use explicit revisions covering all inputs, so caching does not silently remove SwiftUI dependencies. Do not write observable state during body evaluation.
6. Use the projected index to check bounds; preserve existing behavior when the selected ID is missing and at the first/last image.

Correctness coverage: add focused projection tests using existing CullingTestSupport fixtures; cover contextual order/missing IDs/fallback, filename order, rating exclusion, analysis order, empty catalogs, missing selection, boundaries, catalog switch, and invalidation. A deterministic build counter may verify reuse across selection changes. Run existing `ZoomOverlayNavigationContextTests`, `ZoomSessionModelTests`, `ZoomKeyboardControllerTests`, `ZoomOverlayKeyActionTests`, and `ZoomCullingMetadataTests`.

Done when repeated reads and selection-only navigation reuse the ordering while mutations of real ordering inputs rebuild it correctly.

## Change 3 — investigate grid resizing separately

Files: `RawCull/Actors/ScanAndCreateThumbnails.swift`; possibly a small dedicated resizing helper and image/cache tests.

1. Compare current AppKit drawing with an explicit bitmap/Core Graphics downscale using a reusable source CGImage, where available. First verify that source extraction does not introduce extra decode/conversion cost.
2. Preserve the 200-pixel maximum dimension, aspect ratio, no-upscale behavior, orientation and color semantics. Validate pixel dimensions on Retina; `NSImage` logical size is not itself a pixel contract.
3. Preserve cache keys, accounting, grid-cache hits, preview RAM admission ownership, bounded save ownership, cancellation, preload gate order, and security access lifetime.
4. Evaluate with a fresh-process cached preload and a browsing-during-preload run. Do not change JPEG size/quality, global preload concurrency, or interactive disk-save behavior as part of this resizing change.

Regression suites: `ThumbnailProviderTests`, `ThumbnailLoaderConcurrencyTests`, `ThumbnailPreloadGateTests`, `ThumbnailPreloadSaveOwnershipTests`, `ThumbnailCacheIdentityTests`, `DiskCacheAndScanAdmissionTests`, and existing orientation/image-loading coverage. Add visual/pixel fixtures for portrait, landscape, small image, color and orientation as required by the chosen implementation.

Done when image output is correct and controlled Release sampling demonstrates lower grid-preparation cost. Current evidence does not yet establish foreground benefit.

## Build and test execution

No builds or app tests were run during documentation preparation. Before implementation, confirm the tree is clean except for these docs and consult relevant SwiftUI/Swift Testing skill references for any code/test edits. Apply one change at a time.

Use the repository's RawCull scheme, pinned package resolution, macOS destination, coverage disabled, and `-only-testing:RawCullTests/<suite>` for focused suites. Use a dedicated derived-data path under `/tmp`. After focused tests, build the RawCull target in Release. Consult existing Makefile/test plans rather than running the default `make` target, which performs distribution work. Run broader smoke checks if changes affect shared presentation/cache behavior. No release, installation, or publication is part of this plan.

## Before/after protocol

1. Keep this baseline immutable. Save new captures and summaries in a new sibling directory with revision and build UUID. Do not overwrite the 1,198-file reports.
2. Use the same Mac and exact 958 ARWs, storage location, display/window setup, source mode and cache limits. Record missing environment details before the next capture. Keep existing caches unless deliberately running a separate cache-miss experiment.
3. Establish a controlled pre-change Time Profiler baseline, then repeat after each change. Existing SwiftUI recordings are useful diagnostics but cannot be directly compared to a Time Profiler-only run as a clean speedup measurement.
4. Separate workloads: (a) fresh-process catalog opening and full background preparation; (b) 60–90 seconds browsing after preparation finishes; (c) optionally browsing during preparation. Use identical actions, durations and image sequence on each side.
5. For browsing, use fixed sections for grid scrolling, adjacent-image navigation, opening zoom, next/previous navigation, zoom/pan, and return to grid. Note timestamps or add narrowly scoped signposts if instrumentation is later implemented. Stop recording before closing the app.
6. Repeat matched recordings at least three times when quantifying change. Compare per-action latency distributions when markers exist, target inclusive weights normalized to the same operation counts, interactive hang events and matched hitch metrics. Report variability and profiler overhead. Do not use whole-recording duration as load time.
7. If Time Profiler-only omits hitch data, use it for CPU comparison and a separate matching SwiftUI/Hitches pair for responsiveness; do not treat missing hitch tables as zero hitches.
8. If memory becomes a goal, record footprint/Allocations separately. This baseline has no memory measurements suitable for a before/after claim.

Expected first implementation scope: changes 1 and 2, then measure. Keep change 3 separate so image-output correctness and performance can be assessed independently. Do not claim a percentage improvement until matched captures support it.
