# Sharpness Scoring and Focus Mask Review

## Scope

Reviewed the sharpness-scoring, focus-evidence, focus-mask, focus-peaking, calibration, persistence, cache-signature, and relevant UI call paths.

The current pipeline has a solid foundation: bounded batch concurrency, per-file ISO and aperture adaptation, AF-point support, Vision saliency, border exclusion, a multiscale scoring option, and useful numeric tests. The biggest precision gains now come from fixing a few mismatches between the intended algorithm and the implementation, then validating changes on labeled image pairs.

## Executive Summary

The highest-priority issues are:

1. Resolution normalization uses image width instead of the longest side. Portrait and landscape images are pre-blurred differently even when their decoded long edge is identical.
2. The focus-mask UI is no longer an edge mask. It renders radial heat patches, while mask threshold, morphology, calibration, visibility-relaxation, and diagnostics still imply a thresholded Laplacian mask.
3. Burst calibration derives a pixel threshold from image-level sharpness scores. That cannot reliably select the intended percentile of sharp pixels.
4. The generic embedded-preview decode path skips sRGB normalization, unlike the Sony binary-preview and RAW-demosaic paths.
5. Cached and persisted scores can survive scoring-configuration changes because their validity signatures are incomplete or absent.


## P1 Resolution Status

All P1 findings have been addressed:

1. Resolution compensation uses the decoded image's longest side, so portrait and landscape frames receive equivalent pre-blur scaling.
2. The red/orange Focus Mask keeps AF/saliency patch selection but renders thresholded, morphed Laplacian edges inside the selected patches. Diagnostics now report threshold, coverage, and visibility relaxation.
3. Burst calibration samples Laplacian pixel energies and updates only the visual threshold. Core sharpness scoring uses a fixed, versioned gain.
4. Sony previews, generic embedded previews, and RAW-demosaic images pass through one sRGB RGBA normalization boundary before scoring.
5. Burst caches and persisted scores carry a complete versioned scoring signature. Persisted scores also require matching file size and modification date; older unsigned scores remain readable but are treated as stale.

## Findings

### P1: Resolution compensation is orientation-dependent

**Location:** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:718-723`

`buildAmplifiedLaplacian` computes:

```swift
let imageWidth = Float(image.extent.width)
let resFactor = max(1.0, min(sqrt(max(imageWidth, 512.0) / 512.0), 3.0))
```

The comment immediately above describes compensation based on the longer side. The code only uses width. A portrait frame downscaled to a 1024 px long edge gets a smaller blur radius than a landscape frame with the same long-edge resolution. This changes the retained detail and noise energy before the Laplacian stage, so orientation can influence ranking.

**Fix:** use `max(image.extent.width, image.extent.height)`. Add a synthetic orientation-invariance test that scores an image and its 90-degree rotation.

### P1: Focus-mask behavior and controls have diverged

**Locations:**

- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+MaskGeneration.swift:170-390`
- `RawCull/Model/ViewModels/FocusandSharpness/FocusDetectorConfig.swift:29-41`
- `RawCull/Views/Settings/FocusSettingsTab.swift:26-49`

`buildFocusMask` ranks local patches and renders radial gradients with `heatPatch`. It does not threshold the Laplacian into a focus-edge mask. The following settings are unused by this path:

- `threshold`
- `erosionRadius`
- `dilationRadius`
- `guaranteeVisibleFocusEvidence`
- `minimumEvidenceCoverage`

`effectiveVisualThreshold`, `relaxedForVisibility`, and `focusMaskVisualThreshold` are also always reported as `nil` or `false`.

The separate green focus-peaking path does use threshold and morphology. The red/orange focus-mask path is effectively a focus-evidence heat map.

**Fix:** make the product decision explicit:

- If the red/orange overlay is intended to be a heat map, rename it to focus-evidence heat map and move threshold/morphology controls under focus peaking.
- If it is intended to be a precise focus mask, intersect the selected evidence regions with an adaptive thresholded Laplacian mask and populate the diagnostics.

For precision, the second option is stronger: use patches to choose *where* to inspect and thresholded edge energy to show *which pixels* are likely sharp.

### P1: Calibration computes the wrong kind of threshold

**Location:** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskCalibration.swift:14-27, 54-65, 108-111`

Calibration describes a threshold that keeps roughly the top 10% of edges, but it collects one final scalar sharpness score per image and applies a percentile to those image scores:

```swift
let tunedThreshold = min(percentile(scores, thresholdPercentile) * tunedGain, 1.0)
```

That value is then used as a per-pixel threshold by focus peaking. Image-score distributions and pixel-energy distributions are different. Subject weighting, saliency availability, silhouette penalty, and blur attenuation all influence the scalar score, so the resulting threshold is not a calibrated edge threshold.

Calibration also changes `energyMultiplier`, which feeds back into scalar scoring and can affect absolute blur-gate and failure-classification behavior. This makes scores catalog-dependent, not only easier to visualize.

**Fix:** split calibration into two independent concepts:

- **Visualization calibration:** collect sampled Laplacian pixel energies from representative images and derive the peaking threshold from that pixel distribution.
- **Scoring calibration:** avoid catalog-relative gain in the core score, or normalize only after computing stable per-image scores.

### P1: Generic embedded previews skip color normalization

**Location:** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:33-42, 73-87, 145-163`

The Sony binary-preview path and RAW-demosaic path call `normalizeToSRGB`. The generic `decodeThumbnail` fallback returns its `CGImage` directly. This makes scoring dependent on source color space and pixel format for files using the fallback path, including non-Sony formats.

**Fix:** normalize the result of `decodeThumbnail` before scoring. Prefer a single decode boundary that guarantees the same format for every source.

### P1: Score validity is incomplete across cache and persistence

**Locations:**

- `RawCull/Actors/BurstAnalysisCache.swift:19-79`
- `RawCull/Model/ViewModels/RawCullViewModel+Sharpness.swift:40-56`

`BurstSharpnessSignature` omits score-affecting values including:

- `explicitSalientWeightOverride`
- `silhouettePenaltyStrength`
- `afRegionRadius`
- aperture-hint policy version
- ISO-scaling policy version
- Laplacian/scoring algorithm version

Persisted culling scores are loaded by file name without a scoring signature or file modification check. After algorithm changes, settings changes, or source-file replacement under the same name, stale values can appear current.

**Fix:** define a dedicated `SharpnessAlgorithmVersion` and a complete codable scoring signature. Store it with both burst caches and persisted scores. Include file size and modification date for persisted values.

### P2: Scalar scoring and visual evidence choose regions differently

**Locations:**

- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:592-600`
- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+MaskGeneration.swift:232-347`

The final scalar score blends the broad AF region and Vision saliency region. The visual overlay can instead select AF center, AF neighborhood, AF region, saliency, mixed, or global patches. This can produce a badge that says a frame is sharp while the overlay highlights a different locus, or an overlay centered on eye-like detail that did not materially drive the score.

**Enhancement:** promote the local patch analysis into scoring. For wildlife and portraits, include the best AF-local patch and strongest subject-interior patch in the scalar breakdown. Keep the full-frame score as a guardrail, not the primary signal.

### P2: Vision saliency union is often too broad

**Location:** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:175-184`

All salient-object bounding boxes are unioned into one rectangle. With multiple subjects or a distant distraction, the box can include substantial background texture. The broad rectangle then influences saliency scoring and patch search.

**Enhancement:** retain individual salient objects. Rank them by confidence, AF overlap, AF distance, area, and interior detail. For multiple subjects, report which region won instead of collapsing them into one box.

### P2: Full-resolution mode can become disproportionately expensive

**Locations:**

- `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringOptions.swift:169-171`
- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:451-460`

A size value of `0` means no downscale. Scoring then allocates an RGBA float bitmap for the full image and sorts large sample arrays. For high-resolution RAW files this increases memory, latency, and cancellation lag sharply. It does not necessarily improve ranking because noise, JPEG sharpening, and fine-texture aliasing also increase.

**Enhancement:** use a bounded high-precision ceiling, or tile the analysis. Empirically compare 1024, 1536, 2048, and tiled larger samples before exposing unlimited processing.

### P2: Cancellation does not stop detached image work promptly

**Locations:**

- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:30-68`
- `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+MaskGeneration.swift:16-36, 137-167`

The engine wraps work in `Task.detached`. Cancelling the batch prevents result publication but does not cooperatively stop Vision, decode, render, or sort work already running.

**Enhancement:** remove unnecessary nested detached tasks where the caller is already in a task group, and add cancellation checks between decode, Vision, render, and reduction stages.

### P3: RAW-demosaic settings still contain a processing bias

**Location:** `RawCull/Model/ViewModels/FocusandSharpness/FocusMaskEngine+Scoring.swift:94-100`

RAW mode disables `sharpnessAmount` but sets `detailAmount = 0.6`. That may be a reasonable visual default, but it is not a neutral measurement path. It can amplify texture and noise differently across cameras and ISO values.

**Enhancement:** benchmark a neutral RAW profile and document the chosen settings. Keep preview-source and RAW-source scores separate; do not compare their absolute values directly.

### P3: The edge operator can be more robust

**Location:** `RawCull/Kernels.ci.metal:13-42`

The current 8-neighbor Laplacian is fast and useful, but it is sensitive to ringing, JPEG halos, and noise. It also operates on gamma-encoded RGB and combines channel-wise absolute responses.

**Enhancement:** evaluate:

- linear-light luminance before edge measurement;
- a multiscale Laplacian or Laplacian-of-Gaussian;
- gradient coherence or Tenengrad energy alongside Laplacian energy;
- a clipped or robust local noise estimate;
- separate chroma suppression for high-ISO files.

Use labeled ranking accuracy to decide whether the extra complexity earns its cost.

## Recommended Implementation Order

1. Fix longest-side resolution normalization and normalize every decode path to the same color space.
2. Separate focus-evidence heat map from focus-peaking mask in naming, controls, and diagnostics.
3. Replace image-score-derived peaking calibration with sampled pixel-energy calibration.
4. Add a versioned complete scoring signature to burst cache and persisted scores.
5. Reuse local patch evidence in scalar ranking, especially for wildlife and portraits.
6. Evaluate multiscale and linear-light scoring against a labeled dataset.

## Validation Plan

Build a small checked-in or external benchmark manifest with image pairs and expected ordering. Include:

- sharp eye vs soft eye;
- sharp feathers/fur vs sharp background;
- motion blur vs missed focus;
- backlit silhouettes;
- low-contrast subjects;
- high-ISO images;
- portrait and landscape orientations of the same image;
- multiple salient subjects;
- Sony preview fallback, generic preview decode, and RAW demosaic sources.

Measure:

- pairwise ranking accuracy;
- top-1 selection accuracy within bursts;
- false-positive "sharp" badges;
- overlay alignment with AF point and annotated subject detail;
- runtime and peak memory by quality mode.

Add automated tests for:

- orientation invariance;
- decode-path color normalization;
- cache invalidation for every score-affecting config field;
- calibration based on pixel-energy samples;
- focus-mask diagnostics when visibility relaxation occurs;
- stale persisted-score rejection.

## Existing Test Coverage

`RawCullTests/SharpnessScoringTests.swift` already covers many useful numeric contracts: robust-tail behavior, micro-contrast, AF coordinate conversion, evidence-region selection, patch ranking, aperture hints, ISO scaling, score normalization, and concurrent scoring calls.

The main remaining gap is end-to-end image behavior. Numeric helper tests protect formulas, but they cannot establish that a sharper eye beats a sharp branch, that portrait rotation preserves rank, or that an overlay lands on the detail a photographer would inspect.
