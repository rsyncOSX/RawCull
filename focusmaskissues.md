# Focus mask review — 2026-09-08

Reviewed the current RawCull source and PhotoAnalysisKit implementation, without inspecting commit history. The sibling package's `Sources` directory matches the resolved Xcode checkout's `Sources` directory byte-for-byte; RawCull's package lock selects PhotoAnalysisKit 1.3.0.

Original review: the three issues below were **P2 / Medium**. All three have now been fixed in the working trees. No P0 or P1 issue was established by the review.

## Fix status — 2026-09-08

- **Issue 1 fixed:** calibration and mask rendering share `buildFocusMaskDetail`, including native-pixel pre-blur and clamped boundaries. Calibration excludes numerical residue below `1e-6`. RawCull calibrates at a fixed maximum dimension of 1616 pixels, independent of scalar scoring resolution. Masks still use the full decoded preview. Calibration remains specific to the chosen image source and preset; it is not a resolution-independent measure of optical focus.
- **Issue 2 fixed:** cached JPEG/RAW source selection resets loading state and generates the enabled mask before returning.
- **Issue 3 fixed:** the main loupe now observes `effectiveFocusConfig`, invalidating masks when presets change even while the overlay is hidden.
- **Package integration:** RawCull now references the patched sibling `../PhotoAnalysisKit` directly, matching the development setup documented in README. The package changes are in that separate repository and have not been published as a remote version.

Validation completed:

- All 39 PhotoAnalysisKit tests passed. New parameterized regressions cover flat images producing no calibration evidence and calibration responding to blurred detail at two image sizes.
- RawCull built successfully against the local patched package. Selected `PhotoAnalysisKitIntegrationTests`, `FocusImageResolutionPolicyTests`, and `SharpnessScoringTests` passed.
- `git diff --check` passed in both repositories.
- The source-switch and preset UI flows were verified by control-flow review and compilation, not interactive UI automation. No real-photo ground-truth accuracy claim is made.

The original findings below are retained for context; their line numbers refer to the pre-fix source.

## 1. P2 / Medium — Calibration measures a different signal from the rendered mask

**Locations:** `../PhotoAnalysisKit/Sources/PhotoAnalysisKit/FocusMaskCalibration.swift:50–61`; `FocusMaskEngine+MaskGeneration.swift:103–109`; `FocusMaskEngine+Scoring.swift:873–890` (the latter two in the same package source directory).

Calibration calls `buildAmplifiedLaplacian` with the original pre-blur radius and the default `nativeMask: false`. Rendering instead uses `max(0.35, preBlurRadius * 0.52)` and `nativeMask: true`. Calibration therefore measures a more heavily smoothed, resolution-dependent signal, while the overlay thresholds a finer, native-pixel signal. Calibration also samples the expanded, unclamped Gaussian-blur extent; the renderer clamps its input to avoid artificial border edges.

RawCull applies this result directly to `config.threshold` in `FocusMaskModel.applyCalibration`, and calibration uses `effectiveThumbnailMaxPixelSize` in `SharpnessScoringModel.calibrateFromBurst`. Consequently, scoring resolution and synthetic border responses can influence a supposedly calibrated mask threshold independently of the detail being displayed. This matters particularly for AF regions, where the adaptive visual threshold is explicitly capped at the calibrated fallback, potentially accepting weaker edges than intended.

**Suggested correction:** share the rendering detail-signal construction and boundary handling with calibration, and define a consistent resolution policy for the calibration input. Sample only valid image regions.

**Verification case:** calibrate using identical flat images and controlled sharp/blurred patterns at the supported scoring sizes, then render the same fixed-resolution preview. Flat-image borders should not qualify as successful detail evidence, and changes in scoring size should not arbitrarily alter mask acceptance.

## 2. P2 / Medium — Returning to a cached JPEG or RAW preview clears the mask without rebuilding it

**Locations:** `RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:244–246, 425–429`.

Every source change calls `resetFocusMaskImage()`. However, `loadSelectedSourceIfNeeded()` immediately returns when the requested embedded JPEG or developed RAW is already cached. Those branches never call `generateFocusMaskIfNeeded()`. The toggle remains enabled, but the overlay is empty until another event regenerates it.

**Reproduction from control flow:** enable the mask, load the embedded JPEG, switch to the thumbnail, then return to the embedded JPEG. The second JPEG visit clears the previous mask and takes the cache-hit return. The same applies to developed RAW.

**Suggested correction:** regenerate the mask on both cache-hit paths when it is enabled, or drive generation from an identity containing the displayed image and selected source.

**Verification case:** cycle thumbnail → JPEG → thumbnail → JPEG, and repeat for RAW, keeping the focus toggle on throughout. Each source must receive a mask without toggling focus off and on.

## 3. P2 / Medium — Main loupe masks do not invalidate when the photo preset changes

**Locations:** `RawCull/Views/ThumbnailComponents/MainThumbnailImageView.swift:254, 475–497, 506–511`; `RawCull/Model/ViewModels/FocusandSharpness/SharpnessScoringModel.swift:84–88`.

The loupe renders using `effectiveFocusConfig`, but observes only `focusMaskModel.config`. The effective configuration additionally depends on `photoType` and `scoringQuality`. In particular, switching to the landscape preset changes subject isolation to full-frame rendering, along with pre-blur and AF-region settings, without necessarily changing the underlying configuration. The existing mask remains cached by URL, and toggling it off and on also reuses that mask.

This can leave a subject-clipped wildlife mask displayed after choosing landscape, or a full-frame mask after choosing a subject-isolating preset. Comparison and zoom views already observe `effectiveFocusConfig`; the main loupe is inconsistent with them.

**Suggested correction:** observe `effectiveFocusConfig` and invalidate/regenerate the loupe mask when that value changes.

**Verification case:** with an existing visible mask, change only the photo preset between wildlife and landscape. Verify that region coverage and threshold processing refresh in the main loupe, including when the mask was hidden during the settings change.

## Review limits and checked behavior

The original review was static, including the existing focus accuracy tests. The subsequent fixes and executed validation are listed above. Suggested verification cases are not all claimed as executed reproductions.

The current rendering path uses clamped native-pixel filtering, preserves thin edges by default, does not force visibility on weak images, computes coverage after morphology/feathering, and gates confidence on measurable detail. The comparison loader separates display sharpening from its analysis image, and zoom checks image/source/file identity before accepting asynchronous results. These are useful correctness protections, but they do not establish optical-focus accuracy against real-photo ground truth or cover the defects above.
