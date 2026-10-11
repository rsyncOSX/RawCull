# Evaluation repair evidence

## Phase 1 — 11 October 2026

Baseline run: `88E32164-72C2-4943-A55C-F6D2B1AAAE13`, `combined-v2`, Standard, exactInputs, highQualityPreview, review-srgb-v1. The original evaluation remains immutable. `baseline-availability.json` records that the documented export is unavailable on this host. The six named ARWs exist in Downloads; no photographs or model outputs are copied into the repository. They are not routine CI assets.

When the export is available, create a separate local inventory (outside the export) with:

```sh
python3 Scripts/FreezeCombinedReviewBaseline.py --root /path/to/CombinedReview --output /private/tmp/baseline-inventory.json
```

The script records SHA-256/size for each exported JSON/PNG, PNG dimensions/channel format, frozen snapshot/work IDs and decoded stage payloads with source/subject/region/provenance metadata. It reads the source without writing to it and refuses to overwrite an existing inventory. Keep the generated inventory private with the export; it can contain the original snapshot paths and observations. Retaining or committing private photographs requires separate authorization.

The synthetic regression uses the real SubjectMaskFocusScorer on one 128×128 image: left half smooth, right half striped, paired with disjoint 8-bit opaque grayscale masks. The right mask passes through ReviewArtifactStore PNG save/reload. Before repair, both masks select opaque alpha across the interior, giving identical scores and coverage 124×124/128² = 0.9384765625; AF incorrectly belongs to both masks. This is the small-image counterpart of the evaluated 98.78% coverage. The phase-1 commit records these expected failures with Swift Testing known-issue assertions; phase 2 must remove the known issue.

Pinned PhotoAIKit `7f9adfcd69661c6bae4a640c16a4056dfc7393df`, CoreAISAM3Provider.imageForSegment, constructs 8-bit DeviceGray/alpha-none masks from binary 0/255, resizing with nearest-neighbor. Candidate creation retains that CGImage, CombinedReviewExecution encodes it as PNG, ReviewArtifactStore retains bytes, and exactInput reloads through ImageIO. The former scorer draws RGBA and reads alpha: this explains the representation mismatch. This is a source trace plus synthetic retention reproduction, not an installed-model inference result.

Real-image gates remain pending: restore the baseline export and retained inputs, record mask foreground/bounds at each boundary, and independently annotate deer/fawn extents, primary mallard, both sparrows and the rabbit head positive control on the normalized appearance source. No bounds or blanket vertical flip are inferred from the unavailable export. F2 remains a phase-3 registration investigation; neither rectangle arithmetic nor the synthetic F1 regression proves anatomical correctness.

Phase-1 verification: `PYTHONDONTWRITEBYTECODE=1 python3 Scripts/TestFreezeCombinedReviewBaseline.py` — 2 passed. `xcodebuild test -project RawCull.xcodeproj -scheme RawCull -destination 'platform=macOS' -derivedDataPath /private/tmp/RawCull-evaluation-build -clonedSourcePackagesDirPath /private/tmp/RawCull-evaluation-packages -disableAutomaticPackageResolution -only-testing:RawCullTests/SubjectMaskFocusRegressionTests CODE_SIGNING_ALLOWED=NO` — succeeded, regression recorded the expected F1 failure. The real-image acceptance gate remains pending as described above.

## Phase 2 — mask decoding and evidence compatibility

The `mask-foreground-v1` producer contract records the foreground channel, white/opaque polarity, threshold (>16 on 8-bit samples), dimensions, source identity, top-left source raster and no interpolation/resizing. SAM instance output is binary 0/255; supported soft masks retain their byte samples and use the same threshold. Grayscale+alpha, opaque RGB without a declared foreground alpha, non-8-bit formats, CG stencil masks and grayscale decode tables are unsupported. The consumer never substitutes alpha for unknown grayscale semantics. It validates the retained contract against the reloaded raster and appearance source identity. This declares source registration; independent semantic/anatomical verification remains phase 3.

`SubjectMaskForeground` reads grayscale samples with row stride intact, and renders actual alpha into an explicitly ordered RGBA buffer. The same foreground supplies scorer support, AF membership and pixel bounds. Mask/image size disagreement abstains rather than resizing. `emptyForeground`, `insufficientUsablePixels` (<64 interior foreground pixels), `unsupportedEncoding` and `unsafeRegistration` are explicit terminal reasons. Cancellation remains cancellation. Occupancy at or above 95% is retained as suspect with a limitation; it is not an anatomical rejection. Whole-frame fallback still has no subject measurement.

`subject-detail-v2` measurements persist scorer version, mask contract, foreground bounds, total/foreground/interior/usable pixel counts, border width, total foreground coverage and usable interior coverage. The legacy `maskCoverage` name retains its precise meaning: usable foreground centers divided by all raster pixels. The excluded border is max(2, min(width,height)/250); the Laplacian uses a one-pixel image neighborhood around each admitted center. Metrics remain render-dependent and uncalibrated.

Pipeline `combined-v3` versions segmentation, identity, measurement, reconciliation, report and comparison. Crop-observation schema remains combined-v2; source/overview/CLIP schemas remain combined-v1. The changed pipeline identity isolates every work key, including pair comparisons (comparison stage). Compatibility additionally records mask/scorer semantics for affected stages. Actual report/reconciliation dependencies already include measurement terminal work, and selection/pair compatibility is versioned independently. No old artifact is selectively migrated or rewritten.

Historical V1 envelopes and records missing the optional mask/scorer fields still decode. Missing versions remain unqualified. Stored manifests/artifacts retain their original compatibility and remain readable. Resume explicitly explains incompatible mask/scorer semantics and requires a new run; a new run cannot consume legacy measurements. Synthesis prompt rows and selection validation exclude measurements lacking current semantics. This change does not claim that current representation alone establishes photographic registration or focus calibration.

Regression coverage includes grayscale PNG save/reload, disjoint smooth/striped support (smooth mask stops four pixels before the texture transition), equivalent premultiplied-first alpha, empty/sparse/full support, mismatched dimensions, padded rows and raw threshold samples, unsupported RGB, source identity mismatch, repeatability, production scorer metadata save/restore, legacy missing-version decoding, stale measurement rejection in selection, downstream compatibility, historical read/new-run isolation, budgets and resume continuation.

The local installed-model/six-image gates remain pending because the baseline export/masks and independent anatomical annotations are unavailable. No new model inference or photographic qualification is claimed by these commits. CLIP verification and SAM cryptographic-identity audit follow-ups remain open.

Phase-2 final verification (macOS 27.0.1, arm64, Debug, unsigned test build):

```sh
xcodebuild test -project RawCull.xcodeproj -scheme RawCull -destination 'platform=macOS' -derivedDataPath /private/tmp/RawCull-evaluation-build -clonedSourcePackagesDirPath /private/tmp/RawCull-evaluation-packages -disableAutomaticPackageResolution -only-testing:RawCullTests/SubjectMaskFocusRegressionTests -only-testing:RawCullTests/CombinedReviewFeatureTests -only-testing:RawCullTests/ReviewRunContractTests -only-testing:RawCullTests/DeepAIReviewFeatureTests -only-testing:RawCullTests/ReviewImageSourceTests CODE_SIGNING_ALLOWED=NO
```

Result: 60 tests / 81 executions passed, zero failures, skipped tests or expected failures. The former F1 known issue is removed. Baseline inventory tests: 2 passed. `git diff --check`: clean. Installed model probes were not run. These are engineering regression results, not a six-image accuracy assessment or phase-6 resource qualification.
