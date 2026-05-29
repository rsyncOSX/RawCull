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
