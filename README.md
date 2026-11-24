# RawCull

Current project version: **3.5.0**. Build **469**.

**Cull faster. Keep the sharpest frame. Keep your photos private.**

[![macOS 27](https://img.shields.io/badge/macOS-27-000000?logo=apple)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](Licence.MD)

RawCull is a native macOS app for reviewing and culling RAW photographs. It combines fast embedded previews, camera focus points, sharpness scoring, burst comparison, natural-language search, and optional on-device AI—without sending your photos to an external inference service.

> Built for Apple Silicon with Swift 6 and SwiftUI.

## Highlights

| | Feature | What it gives you |
|---|---|---|
| ⚡️ | **Fast RAW review** | Scan catalogs and browse cached thumbnails or full-size embedded previews. |
| 🎯 | **Focus intelligence** | See Sony and Nikon AF points, focus masks, saliency, and sharpness evidence. |
| 🏆 | **Burst ranking** | Group similar frames and surface the strongest candidate with confidence and cautions. |
| 🔍 | **Close-ups** | Compare magnified crops across selected burst frames using recorded autofocus points, detected faces, or manually selected regions. |
| 🔎 | **Search by meaning** | Find photos with natural-language queries using local CLIP embeddings. |
| 🖼️ | **Review** | Ask what is wrong with a photo. Focus check measures subject sharpness with SAM 3 masks; Describe gives a Qwen assessment; Full adds per-object crops and a written report. Tag, rate and mark reviewed from the result. |
| 🤖 | **Burst AI assessment** | Run a local Qwen assessment of the recommended and alternate frame in every burst, with progress and cancel. Results open in the AI Assessments window. |
| ⭐️ | **A complete culling flow** | Tag, reject, rate, filter, compare, and persist your decisions. |
| 📦 | **Flexible export** | Export JPEG previews or copy selected RAW files with live rsync progress. |
| 🔌 | **MCP server** | Query an authorized catalog and retrieve ranked burst recommendations from a compatible desktop AI client. |

RawCull also reads core EXIF data, supports developed RAW previews, caches compatible analysis across sessions, and monitors cache usage and memory pressure.

## Local AI

RawCull's AI features run locally on the Mac. Model downloads and validation are managed by the app; photographs, masks, prompts, and results stay on the device.

| Model | Purpose | Used for |
|---|---|---|
| **DataComp CLIP** | Understands image/text similarity | Semantic search, visual similarity, burst grouping, and coarse subject labels |
| **SAM 3** | Finds where a prompted subject is | Subject masks, AF-point checks, the subject outline, and Review's focus measurement |
| **Qwen3-VL** | Describes and evaluates a photograph | Review's Describe and Full presets, burst AI assessment, and MCP photo assessments |

CLIP image embeddings are computed once and reused for later searches. SAM 3 masks and compatible analysis artifacts can also be cached. Qwen assessments are advisory: RawCull validates their structure, but the photographer remains the final judge.

## RawCull MCP server

The bundled Model Context Protocol (MCP) server lets you work with an authorized RawCull catalog from a compatible desktop AI client such as Codex. You can ask for photo counts, capture dates, and camera information while RawCull is closed. With burst analysis enabled, a prompt can open RawCull, run its on-device analysis, and retrieve ranked burst recommendations and coverage in chat.

You choose which catalog to share and whether the client can start analysis in **Settings → MCP**. The helper runs locally and returns authorized catalog metadata and analysis results. The AI client may send those results to its configured model provider.

A prompt can ask RawCull to set up a catalog, and each job asks for your approval, either for that job only or remembered for later jobs. [Copy-ready prompts](Docs/prompts.md) · [MCP server setup and supported tools](Docs/mcpserver.md)

## Review

Open **Review** from the toolbar, then choose selected or tagged images as the input and a preset:

- **Focus check**: SAM 3 subject masks, focus measurement and CLIP. It does not use Qwen and works without the Qwen model.
- **Describe**: one Qwen assessment of the whole photo.
- **Full**: everything, including per-object crops and a written report.

Each result shows the photo, its findings, and Tag, Rate and Mark Reviewed, with the grid's rating keys. Running or reopening a review never changes a rating. The photo stays in place while the panel beside it drills down: click a finding to see its crop and highlight its region on the photo, then **Region details** for the subject, crop geometry and provenance. The ↑ and ↓ keys step through findings and Esc goes back. Layer toggles under the photo show the regions, the subject mask and the crop geometry. **Coverage & limits**, the full technical record and run history open in a separate, resizable Review Record window that follows the selected photo. While a review runs, a card on the photo shows the current step and a progress bar. Focus check and Full also supply the subject outline (the S key) in the loupe, zoom and burst workspace.

Describe and Full need at least 16 GB of unified memory; 32 GB is recommended.

Saved reviews remain available outside the current input selection. Review settings, retention cleanup, selection comparison, and run diagnostics are available through disclosure controls. The complete structured record can be inspected and copied as JSON.

Findings retain their evidence limits and conflicts. If synthesis fails, available observations are labeled as observations only. Missing retained images do not erase the report or measurements.

## RAW previews

Fit-to-window RAW viewing uses viewport-sized development when a cached developed
JPEG is unavailable. Native zoom and exposure/clipping inspection use full
resolution. Completed previews share a 256 MiB memory cache, and compatible
persisted developed JPEGs can be reused across launches. The current image stays
visible while a higher-resolution preview loads.

## Workflow

```text
Open a RAW catalog
       ↓
Review previews, metadata, focus points, and sharpness
       ↓
Group bursts or search the catalog by description
       ↓
Check candidates with Review: Focus check, Describe or Full
       ↓
Rate, tag, reject, and export the keepers
```

## Requirements

- Apple Silicon Mac
- macOS 27
- Xcode 27 and Swift 6 for development

RawCull is focused on Sony ARW workflows. Its parsing layer also contains Nikon MakerNote support for normalized AF-point extraction.

## Architecture

The app keeps UI, workflow, caching, persistence, and culling policy in RawCull while focused Swift packages own reusable functionality:

| Package | Responsibility |
|---|---|
| [RawParserKit](https://github.com/rsyncOSX/RawParserKit) | RAW discovery, metadata, embedded JPEGs, previews, and MakerNotes |
| [PhotoAnalysisKit](https://github.com/rsyncOSX/PhotoAnalysisKit) | Sharpness, focus masks, saliency, classification, and calibration |
| [PhotoAIKit](https://github.com/rsyncOSX/PhotoAIKit) | CLIP, SAM 3, Qwen, model validation, similarity, and mask storage |
| [RawCullCore](https://github.com/rsyncOSX/RawCullCore) | Shared catalog, EXIF, burst grouping, ranking, and review models |
| [RsyncArguments](https://github.com/rsyncOSX/RsyncArguments) + [RsyncProcessStreaming](https://github.com/rsyncOSX/RsyncProcessStreaming) | Safe copy configuration and streaming execution |
| [DecodeEncodeGeneric](https://github.com/rsyncOSX/DecodeEncodeGeneric) | Codable persistence helpers |

Inside the app, `RawCullViewModel` creates and owns the workspace models. Each model
owns one area of state: `CatalogWorkspace`, `SelectionModel`, `RatingsModel`,
`WorkspacePresentationModel`, `FileOperationsModel`, `ZoomOverlayModel`,
`LoupeViewportModel`, `BurstWorkflowController` and `WorkspaceNavigationModel`.
`CatalogController` and `CullingController` run the operations that span several
models, such as loading and sorting the catalog or rating a photo and moving to the
next one. `workspaceEnvironment(_:)` in
[`RawCullApp.swift`](RawCull/Main/RawCullApp.swift) puts these models, plus the
sharpness, similarity and Review subject-mask models, into the SwiftUI environment. Views
read only the models they need. The only files that use the view model directly are
the view model itself, `RawCullApp`, `RawCullMainView` and the MCP and intelligence
bindings.

Remote dependencies are pinned in [`Package.resolved`](RawCull.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). The current resolved versions are:

| Package identity | Resolved pin |
|---|---|
| `coreai-models` | `1.0.0` |
| `decodeencodegeneric` | `1.0.0` |
| `eventsource` | `1.6.0` |
| `parsersyncoutput` | `1.0.0` |
| `photoaikit` | `3.1.0` |
| `photoanalysiskit` | `1.4.1` |
| `photoevidencekit` | `1.1.5` |
| `rawcullcore` | `1.1.5` |
| `rawparserkit` | `1.3.3` |
| `rsyncarguments` | `1.0.0` |
| `rsyncprocessstreaming` | `1.0.0` |
| `swift-asn1` | `1.7.4` |
| `swift-atomics` | `1.3.1` |
| `swift-collections` | `1.7.5` |
| `swift-crypto` | `4.5.2` |
| `swift-huggingface` | `1.0.0` |
| `swift-jinja` | `3.0.0` |
| `swift-log` | `1.17.0` |
| `swift-nio` | `2.105.0` |
| `swift-sdk` | `0.12.1` |
| `swift-system` | `1.8.1` |
| `swift-transformers` | `1.4.0` |
| `xgrammar` | `0.2.2` |
| `yyjson` | `0.13.0` |

Model manifests, licence notices, and provenance records live in [`ModelAssets`](ModelAssets/README.md).

## Build

Build and export a Debug archive:

```bash
make debug
```

Or build the Xcode scheme directly:

```bash
xcodebuild \
  -project RawCull.xcodeproj \
  -scheme RawCull \
  -destination 'platform=macOS,arch=arm64' \
  -onlyUsePackageVersionsFromResolvedFile
```

## Test

```bash
make test-smoke        # Fast integration and critical-path coverage
make test-full         # Full suite with Thread Sanitizer and serial test execution
make test-performance  # Performance and extreme-concurrency coverage
make test-scripts      # Python script checks; no models or photographs required
```

The Swift Testing suites cover RAW parsing, focus and sharpness metrics, similarity and semantic search, Review, Qwen responses, downloads, caches, persistence, cancellation, concurrency, and copy workflows.

### Troubleshooting: `MDB_MAP_FULL` in the console

You may see many lines like this in the Xcode console, while the app runs or during a test run:

```text
RawCull[38043:206681] mdb_txn_commit error: MDB_MAP_FULL: Environment mapsize limit reached
```

These come from macOS, not RawCull. Metal records which compiled-shader archives an app uses in a small LMDB database (`archiveUsage.db`) in the app's per-user cache folder, and that database has a fixed maximum size. RawCull compiles Core Image Metal kernels, and the test plan creates many Core Image contexts, so the database fills up. After that, every write fails and logs one line. Shaders still compile and run, and test results are not affected.

To clear it:

1. Quit RawCull and stop any running test.
2. Delete RawCull's Metal caches. macOS recreates them on the next launch, and the first launch may be slower while shaders recompile.

   ```bash
   rm -rf "$(getconf DARWIN_USER_CACHE_DIR)no.blogspot.RawCull/com.apple.metal" "$(getconf DARWIN_USER_CACHE_DIR)no.blogspot.RawCull/no.blogspot.RawCull/com.apple.metal"
   ```

To check whether a database is full first, look for `archiveUsage.db/data.mdb` files whose modification time no longer changes while the app runs:

```bash
find "$(getconf DARWIN_USER_CACHE_DIR)no.blogspot.RawCull" -path '*com.apple.metal/archiveUsage.db/data.mdb' -exec stat -f '%z bytes  %Sm  %N' {} \;
```

The message comes back once the database fills again. Nothing in RawCull's code controls its size. To hide the lines meanwhile, type `-MDB_MAP_FULL` in the Xcode console's filter field.

## Performance tools and scripts

Run the opt-in Release benchmark against your own ARW catalog:

```bash
make catalog-performance CATALOG="/path/to/ARW catalog" \
  PERF_ARGS='--output /tmp/rawcull-performance-before'
```

Use a new output directory outside the repository and source catalog. The runner
records logs, JSON measurements, and a Markdown report; it supports comparison
with a compatible baseline. These component timings measure image readiness,
not the first painted frame.

See the [scripts guide](Scripts/README.md) for tool entry points.

A standalone PhotoAnalysisKit comparison on 227 RAW files measured **30% less
time for serial batch analysis** (25.09 s to 17.48 s) and **49% less median time
for combined analysis and focus mask generation** (194.12 ms to 99.38 ms).
The comparison used one run per revision.

## Code knowledge graph

`graphify-out/` holds a [graphify](https://github.com/safishamsi/graphify) knowledge graph of the code. The folder is in `.gitignore`.

### Install and update graphify

graphify is published on PyPI as `graphifyy` (two y's); the command it installs is `graphify`. Install it with [uv](https://docs.astral.sh/uv/):

```bash
uv tool install graphifyy
```

Update it to the latest version:

```bash
uv tool upgrade graphifyy
```

`uv tool install --upgrade graphifyy` does both: it installs graphify if it is missing and upgrades it otherwise.

### Rebuild the graph

Run these from the repository root. The sibling packages `RawCullCore`, `PhotoAIKit` and `PhotoAnalysisKit` must be checked out next to this repository.

1. Delete the cache so every file is parsed again:

   ```bash
   rm -rf graphify-out/cache
   ```

2. Build the full graph:

   ```bash
   "$(cat graphify-out/.graphify_python)" graphify-out/rebuild.py
   ```

The last line it prints gives the counts, about `Graph: 7488 nodes, …`. This writes `graph.json` and `GRAPH_REPORT.md`, which is all that graph queries need.

Use only `rebuild.py`. `/graphify` and `graphify update` scan the app folder alone (about 6,200 nodes) and replace the full graph. Don't delete `rebuild.py`, `label_overrides.json`, `licence_semantic.json` or `.graphify_python` in `graphify-out/`: the rebuild needs them and git doesn't track them.

## Release

### Release checklist

RawCull is released through the App Store. The AI models download as Apple-hosted
Managed Background Assets, which work only in a TestFlight or App Store build, so a
Developer ID DMG cannot download them (see [Developer ID DMG](#developer-id-dmg-not-for-releases)).

Follow these steps for every release:

1. **Automated checks.** Tag the release commit first, then run the checks from a
   clean worktree on that commit. `release-preflight` fails when the `vX.Y.Z` tag for
   the app's `MARKETING_VERSION` is missing or points to another commit. Keep the tag
   local until step 5, so you can move it if a fix is needed.

   ```bash
   git tag -a v3.5.0 -m "RawCull 3.5.0"
   ```

   ```bash
   make release-check
   ```

   It runs these in order and stops at the first failure:

   ```bash
   make release-preflight          # Clean worktree, version, tag on HEAD, model provenance
   make verify-ai-import-boundary  # Restricted AI imports
   make test-mcp-release           # MCP helper tests, plus the shared job stores compiled in Release
   make test-smoke                 # App integration and critical paths
   ```

2. **Build numbers.** Check that the app and the `RawCullModelDownloader` extension
   have the same `CURRENT_PROJECT_VERSION`. `release.sh` sets both when Xcode
   manages build numbers or when `BUILD_NUMBER` is set. `ReleaseMetadataTests`,
   which runs in `make test-full`, fails when the two differ.
3. **Upload to TestFlight.** Use `appstore`, so the build you test is the one you
   later submit (see [App Store Connect and TestFlight uploads](#app-store-connect-and-testflight-uploads)):

   ```bash
   make upload-app-store
   ```

4. **Manual smoke test on the TestFlight build.** Install the build from TestFlight,
   not from Xcode, so the model downloads run as they will for users. The workspace
   state is split into separate models that views read from the SwiftUI environment
   (see [Architecture](#architecture)). The automated tests do not run the full UI,
   so check these by hand:
   - Download the AI models from the app and check that they install and load.
   - Open a catalog. Switch through every view mode: loupe, grid, similarity grid,
     rated grid, comparison grid and Review. Open and close
     the zoom overlay.
   - Rate, tag and reject a photo. Check that the grid, filters and selection update
     and that the next photo is selected.
   - Group bursts and open the burst workspace. Run a Focus check Review on one
     burst and toggle the subject outline (S) in the loupe, zoom and burst workspace.
   - Run Review with each preset (Focus check, Describe and Full) on selected and on
     tagged photos. Focus check must run without the Qwen model installed. In a
     result, tag, rate and mark reviewed, and check that the grid updates. Reopen
     the review and check that the rating has not changed. Click a finding and check
     that its region lights up on the photo and its crop shows beside it; use ↑ ↓
     and Esc, open **Region details**, and open the Review Record window.
   - Rate a photo 4 stars, open its review and check that the tag button reads
     **Tagged** and is disabled, so it can't erase the stars. Check the same in the
     AI Assessments window.
   - After updating from an earlier build, check that the AI Analysis view and the
     "Show legacy AI Analysis" setting are gone and that the app launches cleanly
     with an old Objects mask cache on disk.
   - Copy or export one file.
   - Run one end-to-end MCP job from a desktop AI client: catalog approval, analysis,
     and retrieving the ranked burst recommendations.

   If a check fails, fix it on the branch, move the local tag to the new commit
   (`git tag -f -a vX.Y.Z -m "RawCull X.Y.Z"`) and start again at step 1.
5. **Submit and publish the tag.** Submit the build for review in App Store Connect;
   the upload commands do not do that. Then push the tag:

   ```bash
   git push origin v3.5.0
   ```

### App Store Connect and TestFlight uploads

Build, sign, and upload in one command:

```bash
./Scripts/release.sh internal   # Internal TestFlight testing only
./Scripts/release.sh appstore   # TestFlight and eligible for App Store submission
```

The Makefile equivalents are `make upload-internal` and `make upload-app-store`.
Sign in to your Apple Developer account in **Xcode Settings > Accounts** first.
Both commands use the `AppStore` configuration, automatic signing, and pinned
package versions. They preserve archives and export diagnostics under `build/releases/`.
They do not submit for App Review or publish the app.

Preview either command by adding `--dry-run`. Xcode manages upload build numbers
by default. To specify one explicitly for both the app and its extension, use
`BUILD_NUMBER=400 ./Scripts/release.sh appstore`; choose an unused build number.
For API authentication, set `ASC_KEY_PATH` to your `.p8` file and also set
`ASC_KEY_ID` and `ASC_ISSUER_ID`. Keep the key outside the repository.

After Apple processes the upload, check the build in App Store Connect and assign
it to an internal TestFlight group if automatic distribution is not enabled.
An `internal` upload cannot be used for external TestFlight or App Store submission;
use `appstore` if you want to submit that same tested build later.

### Developer ID DMG (not for releases)

`make build` creates a signed, notarized and stapled app and DMG for direct
download. Don't use it for releases: outside the App Store, the app cannot download
the AI models. It requires the configured Developer ID identity, notarytool keychain
profile, and `create-dmg` at `../create-dmg/create-dmg`.

```bash
make build
```

To verify a downloaded DMG against the generated SHA-256 file:

```bash
make verify-downloaded-dmg \
  DOWNLOADED_DMG=/path/to/downloaded/RawCull.3.5.0.dmg
```

### Local release integration tests

Run `make releaseaiobjectstest` to analyze the ARW files directly in Downloads using installed
Qwen and SAM 3 models, without launching RawCull's UI. A run report
identified by UUID is written as `RawCull-AI-Objects-<UUID>.md` in Downloads.
See [release integration instructions](RawCullReleaseTests/README.md) for model
paths, overrides, and result semantics. The linked guide also contains historical baseline details; use the current Makefile target above for AI Objects.

Additional opt-in checks are available:

```bash
make releasesharpnesstest  # Catalog sharpness report; no Qwen or SAM 3 required
make combinedinputstest   # Combined Review input-contract probes with installed models
make combinedselectiontest # Six-file Sony source/crop probe and selection comparison
```

The catalog-based checks default to `$HOME/Downloads`; override it with
`RELEASE_CATALOG=/path/to/photos`. AI Objects defaults to model bundles under
`$HOME/ModelAssets/Release/Models`; override them with `RELEASE_MODELS`,
`RELEASE_QWEN`, or `RELEASE_SAM3`. Input-contract probes use `INPUT_PROBE_MODELS`
and write to `INPUT_PROBE_OUTPUT` (default `/tmp/rawcull-combined-input-probe`).

## License

RawCull is available under the [MIT License](Licence.MD). The optional AI models retain their respective licences and attribution requirements; see [`ModelAssets/Notices`](ModelAssets/Notices).
