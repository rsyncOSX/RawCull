# Focus Mask Improvement Status

Last audited: 2026-09-08

This document reconciles the original focus-mask findings with the commits
currently present in RawCull and its sibling `../PhotoAnalysisKit` checkout.
“Complete” means the underlying behavior is implemented, not that
photographic accuracy has been validated on a labeled image corpus.

## Current implementation state

| Original priority | Status | Evidence | Assessment |
|---|---|---|---|
| 1. Preserve detail before mask analysis | Complete | RawCull commit `1e6d096` removes the independent 1024-wide reductions and routes zoom/comparison analysis through `FocusMaskAnalysisResolutionPolicy`, whose current policy preserves the decoded image at native dimensions. | Small detail is no longer discarded before PhotoAnalysisKit sees it, and undersized previews are not enlarged. |
| 2. Use the same fine detail for selection and rendering | Complete | PhotoAnalysisKit commit `98a9630` builds one fine-detail `boostedLaplacian` and uses it for rankings, threshold sampling, and rendered edges. Commit `9d6fd40` clarifies that `fineDetailBlendWeight` is scoring-only. | The mask no longer selects a patch with a detail signal that the overlay omits. |
| 3. Avoid visibility and confidence overstating evidence | Complete | PhotoAnalysisKit commit `ee92a17` makes `guaranteeVisibleFocusEvidence` source-compatible only; generated masks never relax their threshold. RawCull commit `3c5c2f0` removes all writes to the obsolete flag. | Confidence requires rendered coverage and measured detail before it can be high. |
| 4. Do not restrict the mask to three representative patches | Complete | PhotoAnalysisKit commit `98a9630` keeps three patch rankings for diagnostics but clips rendered edges to complete evidence search regions instead. | Global mode covers the full image; subject/AF modes intentionally cover their complete selected region. |
| 5. Do not erase or misreport narrow edges in postprocessing | Complete | PhotoAnalysisKit defaults erosion and dilation to zero and feathering to 0.5 px; coverage is measured after processing. RawCull commit `d47108a` adopts those defaults for new settings and legacy files missing the fields. | Explicitly saved nonzero morphology remains a user choice and is not migrated. |
| 6. Keep preview sharpening out of analysis | Complete | RawCull commit `8a0c44d` separates display and analysis images for comparison thumbnails. Commit `91aca7b` supplies the same dedicated unsharpened analysis image to thumbnail zoom. | Enabling display sharpening no longer changes comparison or zoom focus evidence. |
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
- `0831946` replaces the remote package reference and duplicate product entries
  with one local `../PhotoAnalysisKit` dependency.
- `8a0c44d` separates sharpened display pixels from unsharpened comparison
  analysis pixels.
- `1e6d096` preserves native decoded preview resolution for mask analysis.
- `91aca7b` enables thumbnail zoom masks using the dedicated unsharpened image.
- `3c5c2f0` removes obsolete visibility overrides.
- `d47108a` aligns RawCull's new and missing-field morphology settings with the
  package defaults.

### PhotoAnalysisKit

- `98a9630` (“Preserve fine edges and render complete focus evidence
  regions”) implements the shared fine-detail signal, complete-region
  rendering, gentler defaults, and postprocessed coverage.
- `ee92a17` adds conservative measured-evidence confidence gates and removes
  threshold relaxation from rendering.
- `9d6fd40` clarifies the separation between scoring fine-detail blending and
  the mask's dedicated fine-detail pass.
- `FocusMaskAccuracyTests` contains five focused regression tests for weak
  AF-local evidence, rendered coverage, thin edges, full global coverage, and
  artificial border evidence.

## Integration state

RawCull now imports the sibling `../PhotoAnalysisKit` checkout locally. The
project contains one package reference, one PhotoAnalysisKit product dependency,
and one framework build entry. The remote PhotoAnalysisKit pin was removed from
`Package.resolved`; package resolution and a complete Debug build succeeded.

## Implementation plan status

Each completed implementation step was committed locally without pushing,
matching the original workflow.

Steps 1–5 are complete in the commits listed above. Remaining work is external
validation and measurement:

1. **Validate accuracy and performance on real photographs.**
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
PhotoAnalysisKit checkout after the final package documentation update. All
five focused tests passed.

RawCull verification completed during implementation:

- Package resolution using the local sibling dependency and a complete Debug
  build succeeded.
- Comparison analysis-source, zoom image-policy, and PhotoAnalysisKit
  integration tests passed.
- Native resolution-policy tests passed.
- All eight settings persistence tests passed, including package-default
  alignment for new and legacy settings.

This does not establish runtime correctness, UI alignment, or photographic
accuracy. Labeled-photo evaluation and profiling remain necessary before
calling the feature optimal.
