# Scripts

Run commands below from the repository root. Python tools use `python3`; Xcode
runners and Swift diagnostics require the project's macOS development toolchain.
Use `python3 Scripts/<script>.py --help` for each Python CLI's current options
(except `VerifyModelProvenance.py`, which runs its check directly).

## Catalog and preview performance

| Tool | Purpose |
|---|---|
| `RunCatalogPerformance.py` | Build and run the opt-in Release benchmark against a nonrecursive ARW catalog; save logs, JSON, and Markdown, with optional baseline comparison. |
| `ExportCatalogTrace.py` | Export self-contained Instruments XML tables with matching benchmark context. |
| `ValidateCatalogSignposts.py` | Validate independently exported catalog signpost XML, including interval and completion evidence. |
| `AnalyzeGridPreparation.py` | Split version-2 grid measurements by completed preload intervals; report ambiguous boundary crossings as unassigned. |
| `AnalyzeSourceLoadDiagnostics.py` | Join source-load diagnostics to outer measurements and report cancellation separately. |
| `RunRAW9PreviewBenchmark.py` | Compile the production RAW renderer with the pinned parser and measure/validate preview modes on real ARWs. |
| `RAW9PreviewBenchmark.swift` | Swift benchmark implementation compiled by the RAW preview runner. |
| `BenchmarkGridPreparation.swift` | Compare grid preparation on persisted, normalized JPEG thumbnails; compile alongside production `GridThumbnailResizer.swift`. |
| `BenchmarkJPEGEncoding.swift` | Compare JPEG encoding options on persisted thumbnails; compile with `swiftc -O`. |

```bash
make catalog-performance CATALOG="/path/to/ARW catalog" \
  PERF_ARGS='--output /tmp/rawcull-before'

python3 -B Scripts/AnalyzeGridPreparation.py /tmp/rawcull-before
```

Catalog benchmark output must be a new directory outside the repository and source
catalog. To collect source-load journals, add `--source-diagnostics` to the runner;
then analyze the output with:

```bash
python3 -B Scripts/AnalyzeSourceLoadDiagnostics.py /tmp/rawcull-before
```

Summed operation durations can overlap and are neither CPU time nor phase wall
time. Parser round trips include scheduling, waits, I/O, and decoding. Standalone
JPEG diagnostics and preview delivery timings do not establish app first paint
or UI hitch rates.

See the [development summary](../Docs/summary.md) for recorded benchmark and validation results.

## Local AI and review evidence

### Prepare bursts without photo assessments

```sh
python3 Scripts/PrepareBursts.py
```

Or supply paths without interactive prompts:

```sh
python3 Scripts/PrepareBursts.py --catalog /absolute/path/to/catalog --output ~/RawCullPreparedBursts.json
python3 Scripts/PrepareBursts.py --continue ~/RawCullPreparedBursts.json
```

This Python 3.9+ standard-library runner reuses the MCP client in `AssessBursts.py`
(keep both files together). RawCull loads the catalog, computes sharpness and
similarity, groups and ranks bursts, and saves its normal analysis caches. The
script exports **all pages of bursts**, including coverage, recommendations,
alternates, confidence, reasons, cautions, and the ranked candidates exposed by
MCP. Currently that API exposes at most five candidates per burst; `frameCount`
reports the total membership. The export is not a list of every member photo.
No Qwen photo assessments are requested; Qwen installation is unnecessary.
RawCull's normal similarity models and analysis settings still apply.

The default results path is `~/RawCullPreparedBursts.json`. A new output file
starts new analysis, replacing RawCull's shared source result and dependent
assessments. Wait for other RawCull clients to finish first. RawCull may prompt
for catalog approval. An existing output file resumes its saved job and export
cursor; choose a different file to start fresh. `--continue` requires an existing
file and never prompts. `--minutes 15` limits this invocation (default unlimited);
Ctrl+C and time limits leave admitted work running. Resume with the printed
command. Completed exports can be reopened without rerunning analysis. Results
and lock files are created with private permissions.

Use `--helper /absolute/path/to/rawcull-mcp` for a different app installation.
Run `python3 -m unittest discover -s Scripts -p 'TestPrepareBursts.py'` for the
fake-client checks covering pagination, resume, setup replay, and failures.

### Assess bursts without a cloud AI client

Run the interactive Python 3.9+ runner from the repository root:

```sh
python3 Scripts/AssessBursts.py
```

After an interruption or time limit, use the command printed by the runner:

```sh
python3 Scripts/AssessBursts.py --continue ~/RawCullBurstResults.json
```

`--continue` requires an existing file and runs without prompts. Add
`--max-bursts 5` and/or `--minutes 15` to bound that invocation; omitted limits
mean unlimited. The same limit flags also work with the interactive runner.
Continuation recovers this script's saved requests; it cannot discover work
previously done by another client without that client's IDs and records.

`AssessBursts.py` uses only Python's standard library and connects directly to
the signed helper at `/Applications/RawCull.app/Contents/MacOS/rawcull-mcp`.
Use `--helper /absolute/path/to/rawcull-mcp` for a different installation.
It uses RawCull's local Qwen assessments and does not invoke Codex, Copilot,
Ollama, or a cloud model. Wait until any other RawCull client has finished
before running it; RawCull shares a single analysis worker and source result.

The prompts ask for:

- A JSON progress/results file (default `~/RawCullBurstResults.json`). Choose
  the same file to resume, or a different file for a new run.
- An absolute catalog folder path for a new progress file.
- Optional existing catalog and completed source job IDs from the MCP log.
  Supply both to reuse that source. The IDs determine the source; the folder
  path is only a label in this mode. Leaving both blank requests a **new burst
  analysis**, which replaces the shared source result and dependent assessments.
  RawCull may ask for folder selection and approval.
- A maximum number of additional bursts per invocation, and a maximum runtime
  in minutes including setup and burst analysis. Zero means unlimited.

Install Qwen and enable MCP photo assessments in RawCull first. The script
assesses the saved recommendation and alternate (at most two frames) for each
burst in source order, using composition, exposure, and subject visibility.
It prints progress and saves full findings and errors in the JSON file. It
does not independently pick a new winner or assess every frame in a burst.

Requests are checkpointed before submission and replayed with their original
IDs after interruption. Finished entries are skipped on resume. The time limit
and Ctrl+C stop this runner, **not** work already admitted by RawCull; that work
may finish afterward. Resume promptly with the same file to retrieve it. Shared
assessment results expire after 24 hours and become unavailable if the source
is replaced, access is revoked, or results are cleared. Errors stop the runner
and retain progress for inspection; it does not automatically retry failed
assessments with fresh IDs. A separate `.lock` file prevents two runners from
using the same progress file simultaneously. JSON writes are atomic and new
files use private permissions. Keep results outside the repository.

`RunCombinedReviewSix.py` runs the Combined Review regression; despite its name,
it selects all filename-sorted ARWs by default. `--frozen` selects the original
six-file fixture and verifies its recorded hashes.

```bash
python3 -B Scripts/RunCombinedReviewSix.py \
  --directory "/path/to/ARW catalog" --output /tmp/rawcull-review-evidence
```

The runner selects files nonrecursively and requires installed model directories
under `~/ModelAssets/Release/Models`: `Qwen/qwen3_vl_2b`, `SAM3`, and
`CLIP-DataComp`. Override the root with `--models`. `--preflight-only` checks inputs
without invoking Xcode; omit it to run analysis. `--packages` accepts an existing
Swift package cache. Outputs use private permissions and a new directory; existing
evidence is never overwritten. When `--output` is omitted, a unique directory
under `/private/tmp` is used. Retain the reported evidence and logs for review.

| Tool | Purpose |
|---|---|
| `FreezeCombinedReviewBaseline.py` | Inventory an existing review export without copying photographs; retain hashes, decoded JSON payloads, and PNG headers. Requires `--root` and `--output`; set `--run-id` for the intended review. |
| `CompareAFSharpness.py` | Score exported AF crops and compare explicitly labeled within-burst pairs; optional `--pairs` CSV uses `burst,a,b,label` with labels `A`, `B`, `tie`, or `uncertain`. |

See [release integration instructions](../RawCullReleaseTests/README.md) for the
additional Makefile-based real-model and sharpness checks.

## Release and repository checks

| Tool | Command / role |
|---|---|
| `VerifyAIImportBoundary.sh` | `make verify-ai-import-boundary`; requires `rg` and checks restricted AI imports. |
| `VerifyModelProvenance.py` | `make verify-model-provenance`; validates the production model catalog and release evidence. Also used by `make release-preflight`. |
| `VerifyTestEnumeration.swift` | Used by `make verify-smoke-manifest` and `make verify-performance-manifest` before their test runs. |
| `release.sh` | `./Scripts/release.sh internal` or `appstore`; archive, sign, and upload with the AppStore configuration. Add `--dry-run` to inspect commands. |

Uploads require an Xcode Apple Developer account or all three API credentials:
`ASC_KEY_PATH`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`. Optional `BUILD_NUMBER` overrides
both app and extension build numbers. Uploads preserve artifacts under
`build/releases/`; they do not submit for App Review or publish the app. An
`internal` upload is limited to internal TestFlight. See the root
[release guide](../README.md#release) for signing, notarization, and DMG commands.

## Script tests

```bash
make test-scripts
```

These tests use temporary fixtures and mocked Xcode invocations; installed models
and photographs are not required. The explicit `Test*.py` discovery pattern
matters: unittest's default lowercase `test*.py` pattern does not find these files.

| Test file | Coverage |
|---|---|
| `TestAssessBursts.py` | Interrupted and lost-response request replay, skipping finished bursts, and additional-burst limits using a fake MCP client. |
| `TestCompareAFSharpness.py` | Pair labels, direction, ties, missing scores, duplicate pairs and burst IDs; optional crop integration. |
| `TestFreezeCombinedReviewBaseline.py` | Read-only inventory, identity, hashes, decoded payloads, absent exports and PNG headers. |
| `TestModelProvenance.py` | Current release evidence and rejection of malformed, missing, blocked or inconsistent provenance. |
| `TestRunCombinedReviewSix.py` | Catalog/frozen selection, terminal progress, empty inputs, missing evidence and exit codes. |
| `TestRunnerPrivacy.py` | Private output permissions and restoration of the caller's umask on success and failure. |
| `TestRunCatalogPerformance.py` | Catalog manifests, runner configuration, result aggregation, baseline compatibility and failure handling. |
| `TestExportCatalogTrace.py` | Trace table selection, export validation and bundle handling. |
| `TestValidateCatalogSignposts.py` | Catalog interval pairing, completion evidence and invalid exports. |
| `TestAnalyzeGridPreparation.py` | Preload phase assignment, overlapping boundaries and failed grid measurements. |
| `TestAnalyzeSourceLoadDiagnostics.py` | Source-load timing joins, attribution boundaries and cancellation diagnostics. |

The crop integration test skips if OpenCV is unavailable. To exercise it, select
a Python environment with both `cv2` and `numpy`, then run
`make test-scripts PYTHON=/absolute/path/to/python3`.

Swift diagnostics, real-catalog/model runners, and `release.sh` are not executed
by `test-scripts`.

## PhotoAnalysisKit before-and-after catalog evaluation

From the RawCull checkout, run:

```sh
python3 Scripts/RunPhotoAnalysisCatalog.py
```

Use macOS 26 or later, Python 3.9 or later, Xcode with Swift 6.2 or later, and
a local PhotoAnalysisKit clone. The script expects that clone next to RawCull
by default. Pass `--kit-repo` if it is elsewhere.

1. Choose **before** and enter the folder containing your images and a separate
   results folder. Use the pinned PhotoAnalysisKit revision offered by the
   script, or enter a commit or tag available in your local clone.
2. Update the kit in RawCull. Run the same script again, choose **after**, and
   enter the same catalog and results folders. Accept the new pin or enter a
   different local revision. The script checks both the filenames and SHA-256
   hashes and reuses the saved labels and settings.
3. Open `after/review.html` for a side-by-side preview and focus overlay, with
   changed burst winners at the top. Use `after/comparison.csv` for individual
   score and failure changes, and `after/comparison.json` for grouped results,
   outcome counts, calibration, and indicative timings. The `before` and
   `after` folders each contain the full diagnostics and exported masks.
   Existing results are preserved. Use another results folder to start over.

### Label a mixed catalog

Put people, animals, and birds in the same catalog. Group comparable shots into
bursts and label the frames you would keep before viewing the scores:

```sh
python3 Scripts/RunPhotoAnalysisCatalog.py --catalog "/path/to/photos" --make-labels labels.csv
```

- Use a category such as `people`, `animal`, or `bird`. Give each burst a unique
  ID and use the same category for every image in that burst.
- Set `preferred` to `yes` for your preferred frame or frames, and `no` for the
  remaining frames in that burst. A burst contributes to agreement only when
  all frames have labels and there is at least one `yes` and one `no`.
- Optionally mark a calibration subset with `calibration=yes`. With no
  calibration labels the runner samples up to 20 images spread across the
  catalog. Calibration is reported separately from the paired mask comparison.
- Optional `iso` and `aperture` override EXIF. Supply both `af_x` and `af_y`
  in the range 0 to 1 from the visual top-left of the upright preview to
  exercise AF-anchored scoring and masks. Omitted AF coordinates stay absent.

Supply the completed CSV at the **before** prompt or via `--labels labels.csv`.
Unlabeled runs still report scores, outcome counts, and visual differences.
They cannot determine whether a ranking agrees with your judgment.

### What the runner exercises

The Python driver builds the selected kit revision in a temporary Swift package.
The Swift runner uses ImageIO upright thumbnails, scalar and batch analysis,
combined analysis and mask rendering, mask generation with supplied and fresh
evidence, global and raw-energy masks, calibration, face evidence, animal crops,
and Vision feature prints. Feature distances use the first successful frame of
a labeled burst as the reference. Standalone photos use a self-distance check.
Results include missing outputs and decode errors. An outcome requires a
suitable photo and metadata to occur in the catalog. The summary includes zero
counts for unobserved focus-failure and region variants.

The default comparison uses a 1024-pixel preview, the automatic preset,
fast quality, and the same configured threshold of 0.46 for both revisions.
A revision can apply its own threshold policy. Use `--maximum-pixels`,
`--preset`, `--quality`, or `--threshold` on the before run to select different
settings. Run another before/after pair to compare another configuration.

This measures the kit with an identical decoder on both revisions. RawCull's
app-specific RAW preview selection and maker-specific AF extraction are
outside this runner. Timings are descriptive, and mask byte differences
should be inspected visually. Previews and results are written locally.
