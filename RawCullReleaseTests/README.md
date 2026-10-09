# Local release integration

Release baseline: **RawCull 3.2.9**, using the resolved `coreai-models` revision
`1953c4f90ba0214c1abc7bebcb9be5107e329a46`. Both release test plans use
the project’s `Package.resolved`; the complete dependency pins are documented
in the [main README](../README.md).

Run from the repository root:

```sh
make releastest
```

This builds and runs the separate `RawCullReleaseTests` target in Release mode
on arm64 macOS 27 or later. The target is hostless: it has no `TEST_HOST`, app
dependency, app entry point, or SwiftUI views. RawCull's production AI Objects,
Qwen runtime, and RAW loader sources are compiled directly into this target,
so changes to those files are exercised without duplicating the pipeline.
App signing, packaging, and notarization are not part of this command. The
ordinary RawCull, Smoke, and Performance test plans do not include this target.

The default catalog is `$HOME/Downloads`, scanned nonrecursively for regular
files with a case-insensitive `.arw` extension. Any positive number of ARW files
is accepted. Files are processed in filename order, sequentially, using automatic
concept discovery and the same criteria and limits as AI Objects in the app.
Model inference runs locally. Xcode may fetch the project's pinned package
versions during the first build.

The default model bundles are:

- `$HOME/ModelAssets/Release/Models/Qwen/qwen3_vl_2b`
- `$HOME/ModelAssets/Release/Models/SAM3`

To use another installation or catalog:

```sh
make releastest RELEASE_MODELS="/path/to/Models" RELEASE_CATALOG="/path/to/photos"
```

For individually located bundles:

```sh
make releastest RELEASE_QWEN="/path/to/qwen3_vl_2b" RELEASE_SAM3="/path/to/SAM3"
```

Every invocation creates `RawCull-AI-Objects-<UUID>.md` in the photo catalog and
prints its path. The report is written before model initialization, after every
photo, and at completion. It includes model identities, per-photo concepts,
segmentation scores, bounding boxes, object and photo assessments, confidence,
stage timings, unparsed assessment responses, and failures. Existing reports and
ARW files are preserved. An absent or unreadable catalog, no ARW files, or inability
to create the report fails before inference starts.

Missing or invalid models fail the run and are recorded in the report. A failed
photo does not prevent the remaining photos from running. The command returns
nonzero for incomplete or failed analysis. Zero retained objects is a valid
production result and is identified explicitly: crop preparation and assessment
are inapplicable in that case. Success verifies structured pipeline output; it
does not establish the factual accuracy of the AI's descriptions.

Each photo uses fresh in-memory mask storage, without writing to the app's
production caches or settings. The test runner is unsandboxed; production app
entitlements are unchanged. macOS must allow the launching terminal or IDE to
access Downloads. If access is denied, grant the relevant Downloads permission
in macOS Privacy & Security settings.

Two isolated contract tests in this target check file discovery and failure-report
preservation. To run only those without model inference:

```sh
xcodebuild test -project RawCull.xcodeproj -scheme RawCullReleaseTests \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -testPlan ReleaseObjects -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath build/ReleaseObjectTests \
  -only-testing:RawCullReleaseTests/ReleaseAIObjectsTest
```

The real-photo test is enabled only when `RAWCULL_RELEASE_RUN=1` is present in the
test runner environment. The Makefile passes this and the configured paths using
Xcode's `TEST_RUNNER_` environment forwarding. Running the scheme manually without
that flag runs the contract tests and skips model inference.

## Sharpness scoring

```sh
make releasesharpnesstest
# Optional: the same catalog override as the AI Objects run
make releasesharpnesstest RELEASE_CATALOG="/path/to/photos"
```

The sharpness command uses the `ReleaseSharpness` plan and selects
`ReleaseSharpnessTest`; the AI Objects command uses `ReleaseObjects` and selects
the renamed `ReleaseAIObjectsTest`, including its discovery/report contracts
and real AI Objects run. Both use the same hostless Release target
and catalog discovery. The sharpness run requires no Qwen or SAM 3 models.
Every sharpness report opens with a plain-language results summary, ordering
comparisons, the photos most affected by AF information, and a prioritized visual
inspection worksheet. Its conclusion distinguishes valid software execution from
photographic correctness and explains how to build human-ranked regression pairs.
Incomplete runs do not claim a successful full-catalog evaluation.

Its real-photo test is enabled by `RAWCULL_RELEASE_SHARPNESS_RUN=1`, forwarded
by the Makefile. Without that flag the sharpness command runs only its report/numeric contracts.
Running a plan manually without a suite filter runs both suites' contracts;
the independent opt-in flags control the real-photo tests.

Sharpness compiles the production `RawCullPhotoAnalysisAdapter`, scoring options,
RAW loader, and breakdown adapters into the target and uses the pinned
PhotoAnalysisKit algorithm. Metadata supplies ISO (400 when unavailable), aperture,
and actual AF position. Every ARW is analyzed sequentially in 11 scenarios:

- All five presets at Balanced / 1024 px / Embedded Preview / metadata AF.
- Wildlife and Landscape with AF removed, using the same decoding conditions.
- Wildlife with Fast or High Precision quality, keeping 1024 px fixed.
- Wildlife at 2048 px, keeping Balanced quality fixed.
- Wildlife using RAW Demosaic, keeping Balanced / 1024 px fixed.

Each run writes `RawCull-Sharpness-<UUID>.md` in the catalog before analysis,
after each scenario, and at completion. The report includes configuration and
algorithm identity, metadata, final/global/subject/broad AF scores, local patch
scores, final/global ratios, blur sigma, saliency candidate counts, evidence
confidence, selected saliency rectangles, configured silhouette penalty strengths, focus diagnostics,
and timings. Optional evidence is shown as unavailable when the scalar facade
does not supply it; mask-only evidence is not inferred. Failed and unprocessed comparisons are preserved. The command
returns nonzero for failed, invalid, or incomplete scoring. Zero is a valid
score and missing subject/AF evidence remains explicitly unavailable.

These comparisons follow `Docs/sharpness-scoring-review-2026-09-28.md` and do
not change production scoring or tune coefficients. Success verifies execution
and numeric validity, not photographic ranking accuracy. Expert-ranked burst
pairs are still needed to evaluate missing-subject fallback, sharp backgrounds,
small subjects, high ISO, low contrast, motion blur, and silhouettes. ISO/aperture
are recorded rather than varied, and no absolute Sharp/Soft labels are assigned.

## Combined Review input-contract probes

`make combinedinputstest` runs phase 1 diagnostics in the same hostless target,
using **Debug** so the probe can call PhotoAIKit's exact internal CLIP
preprocessor through `@testable import`. It uses the project's pinned package
sources without copying or modifying them. The probe is compiled only in Debug;
the existing Release Objects and Sharpness commands retain their behavior.

The opt-in run requires installed Qwen, OpenAI CLIP, and DataComp CLIP bundles:

```sh
make combinedinputstest \
  INPUT_PROBE_MODELS="$HOME/ModelAssets/Release/Models" \
  INPUT_PROBE_OUTPUT="/tmp/rawcull-combined-input-probe"
```

The model root contains `Qwen/qwen3_vl_2b`, `CLIP-OpenAI`, and `CLIP-DataComp`.
No photographs are required. The probe generates a grid, cyan circle, and four
colored corner markers in landscape, portrait, square, and extreme aspect ratios,
plus all eight EXIF orientations. It checks the actual preprocessors, compiled
input descriptors, Qwen projected image tokens, overview and source-crop paths,
finite/repeatable normalized CLIP embeddings, CLIP text truncation, and Qwen
single-image generation and context/output boundaries.

The output includes `input-contract.json` and denormalized PNG input previews.
The JSON records dependency revisions, source coordinates, effective scale,
normalization, compiled scalar types, Float32 preprocessing hashes, Float16 bound
input hashes where applicable, content fingerprints, model responses, and explicit
unknowns. It is written atomically with incomplete/failed/passed status. The
Float16 conversion matters: CLIP's Float32 preprocessor output is not its bound
encoder tensor. PNGs are viewing aids; use the deterministic probe and recorded
scalar hashes to reproduce numeric inputs.

The only default test in this suite verifies synthetic orientation handling.
Model inference runs only with `RAWCULL_INPUT_PROBE_RUN=1`, forwarded by the
Makefile. The suite is outside the app's ordinary unit and smoke plans. A passed
input contract establishes geometry and runtime behavior for these exact assets;
it does not establish photographic accuracy or qualify alternate encoder shapes.
See [the phase 1 diagnostic decision](../Docs/combined-review-input-contract.md).
