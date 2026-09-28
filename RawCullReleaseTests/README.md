# Local AI Objects release integration

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
  -only-testing:RawCullReleaseTests/ReleaseRunnerTests
```

The real-photo test is enabled only when `RAWCULL_RELEASE_RUN=1` is present in the
test runner environment. The Makefile passes this and the configured paths using
Xcode's `TEST_RUNNER_` environment forwarding. Running the scheme manually without
that flag runs the contract tests and skips model inference.
