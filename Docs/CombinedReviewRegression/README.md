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
