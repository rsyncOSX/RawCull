# Focus Mask Improvement Status

Last audited: 2026-09-08

This document reconciles the original focus-mask findings with the commits
currently present in RawCull and its sibling `../PhotoAnalysisKit` checkout.
“Complete” means the underlying behavior is implemented, not that
photographic accuracy has been validated on a labeled image corpus.

## Current implementation state

| Original priority | Status | Evidence | Assessment |
|---|---|---|---|
| 1. Preserve detail before mask analysis | Remaining | `ZoomOverlayView.regenerateMaskFromCG` and `ComparisonGridImageCoordinator.focusResult` both call `downscaled(toWidth: 1024)` before analysis. | This remains the largest accuracy gap. A width-only cap still loses small detail and creates inconsistent portrait/landscape analysis resolution. |
| 2. Use the same fine detail for selection and rendering | Complete | PhotoAnalysisKit commit `98a9630` builds one fine-detail `boostedLaplacian` and uses it for rankings, threshold sampling, and rendered edges. | The mask no longer selects a patch with a detail signal that the overlay omits. The configuration comment for `fineDetailBlendWeight` is now stale: overlay generation no longer uses the primary scoring pass. |
| 3. Avoid visibility and confidence overstating evidence | Mostly complete | PhotoAnalysisKit commit `ee92a17` makes `guaranteeVisibleFocusEvidence` source-compatible only; generated masks never relax their threshold. Confidence requires rendered coverage and measured detail before it can be high. | The engine behavior is correct. RawCull still assigns `guaranteeVisibleFocusEvidence = true` in Zoom and for sharp comparison images, but this no longer changes engine output and should be removed during cleanup. |
| 4. Do not restrict the mask to three representative patches | Complete | PhotoAnalysisKit commit `98a9630` keeps three patch rankings for diagnostics but clips rendered edges to complete evidence search regions instead. | Global mode covers the full image; subject/AF modes intentionally cover their complete selected region. |
| 5. Do not erase or misreport narrow edges in postprocessing | Complete | Default erosion and dilation are zero; the unconditional final erosion has been removed; default feathering is 0.5 px; coverage is measured on the rendered result after processing. | Explicit nonzero morphology still deliberately changes the result, and the rendered-coverage diagnostic reflects that result. |
| 6. Keep preview sharpening out of analysis | Remaining | `ComparisonImageLoader.loadThumbnail` returns a sharpened `CGImage` when enabled, and `ComparisonGridImageCoordinator.analyzeFocus` analyzes that same image. | The thumbnail display preference can still change focus evidence. Zoom thumbnail mode currently has no `CGImage` mask analysis path, so its focus-mask control is misleading/unavailable rather than incorrectly analyzing the sharpened thumbnail. |
| Performance: reuse overlap computations | Remaining | `patchRankings` samples each overlapping patch independently from the already-rendered energy image. | No benchmark or cache exists. Defer until the accuracy changes are measured. |

## Work already committed

### RawCull

- `5395108` makes thumbnail-overlay availability more accurate and clears
  stale zoom masks when image/source state changes.
- `6f3ac62` updates the RawCull build version.
- `921b7fb` makes the zoom-mask task identity include image, source, and
  file, preventing stale asynchronous results from being applied.
- `55ff38b` adds an embedded-preview fallback and adjusts zoom image handling.
- `c487e43`, `402b72b`, and `61b59eb` transition the PhotoAnalysisKit package
  reference to the released remote version `1.3.0`, which resolves commit
  `ee92a1795532374a482eb0c388943a761b9f6c45`.

### PhotoAnalysisKit

- `98a9630` (“Preserve fine edges and render complete focus evidence
  regions”) implements the shared fine-detail signal, complete-region
  rendering, gentler defaults, and postprocessed coverage.
- `ee92a17` adds conservative measured-evidence confidence gates and removes
  threshold relaxation from rendering.
- `FocusMaskAccuracyTests` contains five focused regression tests for weak
  AF-local evidence, rendered coverage, thin edges, full global coverage, and
  artificial border evidence.

## Integration concern to resolve first

RawCull no longer imports the sibling package locally. Its project currently
references the released remote package at `1.3.0`, which contains the package
changes. That is a valid release integration, but it differs from the original
instruction to use `../PhotoAnalysisKit` locally until the import is updated.

`RawCull.xcodeproj/project.pbxproj` also contains three
`PhotoAnalysisKit` product dependencies and three framework build-file
entries. Only one remote package reference is present. The extra unbound
product references should be removed and the target left with exactly one
PhotoAnalysisKit product dependency before additional package work. This
avoids ambiguous or duplicate linking.

## Detailed remaining plan

Each numbered implementation step should be committed locally without pushing,
matching the original workflow.

1. **Normalize package integration.**
   - Decide whether the next package iteration is local (`../PhotoAnalysisKit`)
     or released remote (`1.3.0`).
   - Remove the two unbound PhotoAnalysisKit product dependencies and their
     framework build-file entries.
   - Keep one package reference, one product dependency, and one framework
     entry.
   - Resolve packages and build the RawCull target to verify the project graph.
   - Commit only the package-reference normalization.

2. **Introduce a dedicated, unsharpened analysis image.**
   - Change `ComparisonImageLoader` to return separate display and analysis
     images, or add a dedicated analysis loader used by
     `ComparisonGridImageCoordinator`.
   - For thumbnail source, request/load the orientation-normalized thumbnail
     before `ThumbnailSharpener` and pass that as the analysis image; retain
     the sharpened result only for display.
   - Preserve cancellation and source-change generation guards so display and
     analysis results cannot be mixed between files.
   - Add a unit test that enables thumbnail sharpening and proves the image
     passed to focus analysis is the unsharpened source.
   - Commit the loader/coordinator change and its test.

3. **Replace the fixed 1024-pixel mask-analysis cap.**
   - Remove `downscaled(toWidth: 1024)` from the zoom and comparison focus-mask
     call paths.
   - Analyze the decoded preview at its native dimensions initially. Do not
     enlarge undersized previews.
   - If profiling requires a cap, add one explicit, aspect-ratio-preserving
     maximum-pixel policy to `FocusMaskModel`/PhotoAnalysisKit instead of
     independent width-only limits. Its default should preserve native detail
     for zoom and comparison.
   - Update or replace `FocusImageDownscalingTests`, which currently asserts
     the obsolete 1024-pixel behavior.
   - Commit this resolution-policy change separately.

4. **Make thumbnail zoom behavior coherent.**
   - Either supply an unsharpened `CGImage` analysis input for thumbnail zoom
     and show its aligned mask, or disable/hide focus-mask controls when the
     active image is only `zoomOverlayNSImage`.
   - Prefer the first option if a thumbnail zoom mask is an intended feature;
     otherwise make unavailability explicit in accessibility/help text.
   - Add a view-model/coordinator regression test for the selected behavior.
   - Commit the thumbnail-zoom behavior separately.

5. **Remove obsolete visibility configuration and clarify configuration docs.**
   - Remove RawCull writes to `guaranteeVisibleFocusEvidence`, since the
     PhotoAnalysisKit property no longer affects rendering.
   - Update `SharpnessConfiguration.fineDetailBlendWeight` documentation to
     distinguish scoring behavior from the mask’s dedicated fine-detail pass.
   - Retain the source-compatible package field only if external clients
     require it; otherwise schedule its deprecation for a breaking package
     release.
   - Commit the cleanup separately.

6. **Validate accuracy and performance on real photographs.**
   - Assemble a versioned, labeled corpus covering eyes, feathers, low-detail
     subjects, portrait and landscape orientations, ISO ranges, and varying
     subject sizes.
   - For each image, record whether highlighted pixels overlap manually
     identified sharp detail; separately record false highlights on noise,
     halos, and background texture.
   - Compare the prior 1024-wide path with native-resolution analysis for
     recall, precision, latency, and peak memory.
   - Profile overlapping-patch sampling only after this baseline exists. If it
     dominates, cache/reuse a rendered energy buffer and verify masks are
     pixel-equivalent before and after the optimization.

## Verification completed in this audit

`swift test --filter FocusMaskAccuracyTests` was run in the sibling
PhotoAnalysisKit checkout. The build completed and all five focused tests
passed. `xcodebuild -list -project RawCull.xcodeproj` also resolved the remote
PhotoAnalysisKit `1.3.0` package successfully.

This does not establish runtime correctness, UI alignment, or photographic
accuracy. The remaining RawCull integration changes require targeted RawCull
tests plus labeled-photo evaluation before calling the feature optimal.
