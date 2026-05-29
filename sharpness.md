# Sharpness and Focus Mask Plan

## Current Problem

RawCull's sharpness scoring is more convincing than the current focus mask overlay. A file can be tagged `Sharp` because the score finds strong subject or AF-region detail, while the red focus mask still shows little or nothing useful. That is a user-facing failure: if RawCull says an image is sharp, the focus mask should help the user understand where the useful focus is.

The focus mask should not be treated as a decorative edge detector. Its purpose is verification: show the photographer which part of the subject appears in focus, especially around the AF point, eye, head, feathers, fur, or other fine subject detail.

## Why The Overlay Still Fails

The current overlay is still too dependent on a thresholded Laplacian pixel mask. Even after including AF and saliency regions, it can fail when the sharp detail is:

- low contrast, such as grey feathers against grey sky;
- small, such as a bird eye or facial feather detail;
- present in the score distribution but below the visual mask threshold;
- weakened by pre-blur, morphology, or downscaling;
- competing against stronger body, wing, tail, or silhouette edges.

The sharpness score can be good while the mask looks empty because scoring reduces a distribution of samples into a robust number, while the overlay asks individual pixels to survive thresholding and post-processing. Those are not the same operation.

## What We Should Do

### 1. Treat The Score As The Source Of Truth

The sharpness score should remain the primary decision maker for `Sharp`, `Good`, `Check`, and `Soft`. The mask should become an explanation layer for that score.

For every image tagged `Sharp`, the mask generation should ask:

> Which region most strongly justified this sharpness result?

That answer should drive the overlay. If AF score wins, show AF-region detail. If saliency score wins, show subject detail. If global score is unusually strong but subject evidence is weak, show that clearly as a lower-confidence whole-frame/detail overlay rather than pretending an eye/subject mask exists.

### 2. Generate A Score-Explainer Mask, Not A Generic Mask

Add a dedicated overlay mode that visualizes the scoring evidence:

- Render the same Laplacian energy used for scoring.
- Sample the same regions used for scoring: full frame, saliency, AF.
- Find the region that contributed most to the final score.
- Build the overlay from the top scoring percentile inside that winning region.
- Use a fallback visibility rule: if an image is tagged `Sharp`, the winning scoring region must produce some visible overlay unless the image data is unavailable.

This does not mean painting every sampled pixel. It means making the overlay explain the scoring decision with enough visual evidence that the user trusts the label.

### 3. Separate Two Overlay Products

There are really two different tools hiding under one button:

- **Focus Evidence Overlay:** shows what justified the sharpness score. This should be the default.
- **Raw Edge Mask:** shows raw high-frequency edges. This is useful for debugging, but not ideal for photographers.

The photographer-facing overlay should be conservative, readable, and score-aligned. The debug overlay can remain more literal.

### 4. Add Minimum Visibility For Sharp Images

If `SharpnessLabel == .sharp`, the focus evidence overlay should not be allowed to silently disappear. A practical rule:

- First try the normal adaptive threshold in the winning region.
- If the resulting mask coverage is below a small minimum, lower the threshold within that same region.
- If still empty, render a subtle focus-evidence contour or glow around the highest-scoring local patch.

This should not fake sharpness. It should only reveal the strongest evidence already found by the scoring pipeline.

### 5. Add Local Patch Analysis Around AF

For wildlife, small local detail matters more than broad edges. The overlay should run local patch analysis around AF:

- AF center patch: eye/head candidate area.
- Slightly larger AF neighborhood: head/upper body context.
- Saliency region: subject fallback.

If the AF patch has strong robust-tail score, the mask should prioritize it even if body or tail edges have higher raw contrast.

### 6. Preserve The Current Score, But Add Better Diagnostics

The debug panel should show:

- final score;
- label threshold result;
- winning evidence region: AF, saliency, global, mixed;
- mask threshold actually used;
- mask coverage percent;
- whether the overlay threshold was relaxed for visibility.

This will make future failures much easier to reason about.

## Is The Current Sharpness Scoring The Best We Can Do?

No, not theoretically. It is probably a good pragmatic approach for the current product constraints, but it is not the absolute best possible sharpness model.

The current scoring is good because it is fast, deterministic, GPU-assisted, and works from the embedded camera JPEG preview. For culling, that is a strong tradeoff. It avoids the huge cost of demosaicing every RAW file and still gives useful results across bursts.

But there are better possible approaches:

- **RAW-based scoring:** demosaic with `CIRAWFilter` and score the actual RAW image. More accurate, much slower.
- **Eye/head detection:** detect subject eyes or heads and score those patches directly. Better for birds and wildlife, but harder and more model-dependent.
- **Burst-relative scoring:** compare nearby burst frames against each other using local detail around AF/saliency. Very useful for culling because absolute sharpness matters less than "which frame is best in this burst."
- **Motion blur detection:** distinguish directional motion blur from missed focus more explicitly.
- **Multi-scale detail scoring:** combine fine, medium, and coarse detail passes so small eye detail and larger feather/body structure both contribute properly.

My view: keep the current scoring as the baseline, but evolve it in two directions:

1. Make the overlay explain the current score convincingly.
2. Add burst-relative and AF-local refinements before attempting expensive RAW demosaic scoring.

## Proposed Implementation Roadmap

### Phase 1: Make Overlay Explain The Score

- Add a `FocusEvidence` result alongside `SharpnessBreakdown`.
- Record per-region score contributions from full, saliency, and AF.
- Mark the winning evidence region.
- Generate the default overlay from that winning region.
- Guarantee minimum visible evidence for images labeled `Sharp`.

Success criteria:

- A `Sharp` image normally shows a visible focus evidence overlay.
- The overlay appears near AF/subject detail, not only broad silhouette edges.
- Debug panel explains why a region was selected.

### Phase 2: Add Coverage And Visibility Metrics

- Measure mask coverage inside AF and saliency regions.
- Store the effective threshold used.
- Store whether threshold relaxation was needed.
- Add tests for "sharp score must produce visible evidence."

Success criteria:

- Empty masks on sharp images become test failures unless explicitly justified.
- Debugging future examples is much faster.

### Phase 3: Improve Wildlife-Specific Local Scoring

- Add AF-centered local patch scoring at two scales.
- Prefer AF-local score for bird/wildlife overlays.
- Keep saliency as fallback when AF is missing or unreliable.

Success criteria:

- Bird eye/head detail is favored over tail/wing/body edges.
- Backlit or low-contrast birds still show useful evidence when the score is sharp.

### Phase 4: Burst-Relative Sharpness

- For burst groups, compare each image against nearby frames using the same AF/saliency patches.
- Use relative ranking to improve labels when absolute scores are close.
- Surface "best in burst" confidence separately from absolute sharpness.

Success criteria:

- The app is better at choosing the best image among similar sharp frames.
- Sharpness labels remain stable, but culling decisions improve.

### Phase 5: Consider RAW-Based High Precision Mode

Only after the overlay and burst-relative scoring are solid, consider an optional high-cost RAW scoring mode.

This should be opt-in because it will be much slower. It may be useful for final verification, but it should not block fast culling.

## Recommended Direction

Do not chase a prettier red mask first. Make the mask accountable to the scoring result.

The right target is:

> If RawCull says "Sharp", the user should immediately see why.

That means the focus mask should become a score explanation overlay, with AF/subject evidence as the first-class concept. Once that is reliable, visual polish can follow.

## Revision Plan After Phase 1-5 Test Images

### What The New Screenshots Show

The current implementation is still not aligned enough with the computed values. The ranking/scoring can identify the better frame, and RAW demosaic scoring appears broadly similar to extracted/embedded JPEG scoring while taking much longer. That suggests the main remaining problem is not "use RAW and the answer becomes obvious." The problem is that the focus overlay is still a pixel-threshold visualization, while the score is a robust regional statistic.

Observed failure mode:

- The AF marker is on or near the eye/head.
- The overlay often paints beak, throat, chest, or lower-head contrast.
- The overlay sometimes reports global or subject evidence while the user expects AF/eye evidence.
- RAW scoring does not substantially change the result, so the current embedded preview is likely good enough for the culling score.
- The mask is still too dependent on where the strongest local Laplacian pixels are, not where the score says useful focus evidence lives.

Conclusion: Phase 6 should make the overlay less like an edge mask and more like a score-aligned evidence annotation.

### Phase 6 Goal: Make Focus Evidence Auditable

Before changing more thresholds, add enough diagnostics to answer these questions for every displayed image:

1. Which score source was used: embedded preview or RAW demosaic?
2. Which evidence region won: AF center, AF neighborhood, AF point, saliency, global, or mixed?
3. What were the actual scores for each candidate region?
4. What patch was visualized on screen?
5. Did the visualized patch contain the AF point?
6. How far is the overlay center from the AF marker in image-percent coordinates?
7. Did the overlay choose the same region that affected the final score?

Add debug fields:

- `visualizedRegion`: the region actually rendered, not only the winning score region.
- `visualizedRect`: normalized rect used for the overlay.
- `visualizedCentroid`: normalized centroid of the rendered mask.
- `afDistanceFromCentroid`: normalized distance from AF point to rendered mask centroid.
- `patchRankings`: sorted list of candidate patches with score, coverage, and distance to AF.

Success criteria:

- For an AF-local winner, the debug inspector must show an overlay centroid close to the AF point.
- If global wins, the UI must say global clearly, and the overlay should not pretend to be eye/head evidence.
- If the overlay paints below the AF box, diagnostics must explain whether the score winner was actually lower-head/body detail or whether the visualizer drifted.

### Phase 7: Replace Threshold Mask With Patch Evidence Overlay

The current red mask marks pixels above a threshold. That is too unstable for low-contrast wildlife. Instead, build a patch evidence overlay:

1. Divide the selected evidence region into overlapping local patches.
2. Score each patch using the same robust-tail and micro-contrast helpers as the sharpness score.
3. Rank patches by:
   - robust-tail score;
   - micro-contrast;
   - distance to AF point;
   - inside/head-like saliency weighting when available;
   - penalty for silhouette/border-only edges.
4. Select the best one to three patches.
5. Render a soft bounded heat patch or contour around those patches instead of thresholding every edge pixel.

For AF-local evidence:

- Start with AF center.
- If weak, expand to AF neighborhood.
- Prefer patches closest to AF unless their score is clearly worse.
- Penalize lower beak/chest patches when they are far from AF and only win because of strong contrast.

For saliency evidence:

- Use patch ranking within the saliency rect.
- Prefer interior detail over outer silhouette edges.
- Avoid large masks that cover broad body surfaces.

For global evidence:

- Render a low-confidence "global detail" overlay style.
- Keep it visually distinct from AF/subject focus evidence.
- Do not use global evidence to imply eye/head focus.

Success criteria:

- Bird eye/head evidence appears as a small, bounded patch near the AF marker when AF-local scores justify it.
- Beak/chest/body contrast does not dominate AF-local overlays unless it genuinely wins and diagnostics say so.
- The overlay is readable at 200-300% zoom without filling large body areas.

### Phase 8: Introduce A Focus Evidence Confidence Model

Add a small confidence result separate from the sharpness label:

- `high`: AF-local or subject patch evidence is strong and spatially aligned.
- `medium`: saliency/global evidence is strong, but AF-local evidence is weak or absent.
- `low`: score exists, but overlay evidence is ambiguous or global-only.

This confidence should not replace the sharpness label. It should explain how trustworthy the focus-location explanation is.

Suggested fields:

- `focusEvidenceConfidence`
- `focusEvidenceConfidenceReason`
- `spatialAlignmentScore`
- `localPatchDominance`
- `silhouettePenaltyApplied`

Success criteria:

- A sharp image can still be sharp while focus-location confidence is medium or low.
- The UI can say "Sharp, but evidence is global" instead of drawing a misleading red patch.
- Burst decisions continue to use sharpness score, but comparison UI can warn when focus evidence is not eye/head-local.

### Phase 9: Eye/Head Candidate Heuristic Before ML

Do not jump straight to a heavy model. First add a deterministic wildlife heuristic:

1. Use AF point as the anchor.
2. Search a small window around AF for compact circular/high-detail structures.
3. Favor patches with:
   - local contrast ring-like detail;
   - small dark/light transitions;
   - texture around the eye/head;
   - proximity to AF;
   - saliency membership.
4. Penalize:
   - long straight beak edges;
   - large silhouette edges;
   - broad wing/tail/body boundaries;
   - patches below AF when AF is on the eye/head and the candidate is much farther away.

This can be implemented as a patch scorer, not as object detection.

Success criteria:

- The Accipiter/goshawk-style examples place evidence around eye/head when AF marker is there.
- Beak and throat remain secondary unless no eye/head evidence is measurable.
- Works from embedded preview first; RAW mode is optional comparison, not the primary solution.

### Phase 10: RAW Mode Decision

Based on the current test, RAW demosaic scoring is slower and roughly equal to extracted/embedded preview scoring for these examples. Keep RAW mode, but treat it as a verification tool rather than the main path.

Recommended policy:

- Default: embedded preview scoring.
- Optional: RAW demosaic scoring for manual verification or small final sets.
- Do not use RAW demosaic to fix overlay alignment.
- Do not spend more effort on RAW scoring until patch evidence overlay is correct.

Success criteria:

- RAW mode can be used to compare scores, but the overlay behavior should be good in embedded-preview mode.
- If RAW and embedded disagree, diagnostics should show both source and region evidence, not just one final label.

### Proposed Implementation Order

1. Add diagnostics for visualized region, rect, centroid, and distance to AF.
2. Add deterministic patch-scoring helpers and tests with synthetic patch grids.
3. Replace AF-local overlay rendering with patch evidence overlay.
4. Add focus evidence confidence and UI rows.
5. Add saliency patch ranking and silhouette/interior penalties.
6. Add global-evidence visual style that is clearly not AF/eye focus.
7. Re-test the same four screenshots/burst files before changing any scoring labels.

### Test Fixtures To Build

Create synthetic numeric tests first:

- AF point at center, strongest patch at AF: overlay patch must select AF.
- AF point at center, stronger beak-like edge below AF: AF patch should still win unless the score gap is large.
- Saliency-only image: best interior patch wins over silhouette border.
- Global-only image: confidence is low/medium and overlay style is global.
- Sharp image with no visible patch: confidence low, no fake AF evidence.

Then validate with real files:

- The four bird screenshots from 2026-05-29.
- One clearly eye-sharp frame.
- One chest/beak-sharp but eye-soft frame.
- One global/landscape frame.
- One frame where RAW and embedded preview disagree.

### Non-Goals For The Next Pass

- Do not change persisted sharpness score format.
- Do not change existing label thresholds.
- Do not make RAW scoring the default.
- Do not add ML eye detection yet.
- Do not tune thresholds blindly without new diagnostics.

### Decision Point Before Implementation

Before coding Phase 6/7, decide:

- Should the red overlay remain a pixel mask, or should AF-local evidence become a bounded patch/heat indicator?
- Should global evidence be shown in red, or with a different style to avoid implying exact subject focus?
- What maximum allowed AF-to-overlay-centroid distance is acceptable for AF-local evidence?
- Should "Sharp but global-only" be allowed to rank highly in burst culling, or should it require manual review?
