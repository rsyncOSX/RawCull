# RawCull

Current project version: **3.4.9**. Build **463**.

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
| 🧠 | **Deep Review** | Use SAM 3 to isolate the subject and compare detail where it matters. |
| 🖼️ | **Combined Review** | Review selected or tagged photos with retained images, findings, supporting crops, coverage limits, and a structured technical record. |
| ✨ | **AI photo critique** | Ask Qwen3-VL to assess composition, exposure, visibility, expression, strengths, and problems. |
| 🔢 | **Objects analysis** | Ask Qwen to suggest visible concepts, segment their instances with SAM 3, and assess a numbered review board. |
| ⭐️ | **A complete culling flow** | Tag, reject, rate, filter, compare, and persist your decisions. |
| 📦 | **Flexible export** | Export JPEG previews or copy selected RAW files with live rsync progress. |
| 🔌 | **MCP server (in development)** | Query an authorized catalog and retrieve ranked burst recommendations from a compatible desktop AI client. |

RawCull also reads core EXIF data, supports developed RAW previews, caches compatible analysis across sessions, and monitors cache usage and memory pressure.

## Local AI

RawCull's AI features run locally on the Mac. Model downloads and validation are managed by the app; photographs, masks, prompts, and results stay on the device.

| Model | Purpose | Used for |
|---|---|---|
| **DataComp CLIP** | Understands image/text similarity | Semantic search, visual similarity, burst grouping, and coarse subject labels |
| **SAM 3** | Finds where a prompted subject is | Subject masks, AF-point checks, and detail-aware Deep Review |
| **Qwen3-VL** | Describes and evaluates a photograph | Structured photo assessment against editable criteria |

In **AI Analysis › Objects**, RawCull uses Qwen to identify photographically relevant concepts, SAM 3 to segment matching visible instances, and Qwen to assess those numbered subjects locally on your Mac. Specific concepts can be entered manually. Results describe matches for the requested concepts; they are not a guaranteed inventory of every object in the scene.

CLIP image embeddings are computed once and reused for later searches. SAM 3 masks and compatible analysis artifacts can also be cached. Qwen assessments are advisory: RawCull validates their structure, but the photographer remains the final judge.

## RawCull MCP server (in development)

The bundled Model Context Protocol (MCP) server lets you work with an authorized RawCull catalog from a compatible desktop AI client such as Codex. You can ask for photo counts, capture dates, and camera information while RawCull is closed. With burst analysis enabled, a prompt can open RawCull, run its on-device analysis, and retrieve ranked burst recommendations and coverage in chat.

You choose which catalog to share and whether the client can start analysis in **Settings → MCP**. The helper runs locally and returns authorized catalog metadata and analysis results. The AI client may send those results to its configured model provider.

Prompt-driven catalog setup, job approval, and saved-grant reuse have been verified on TestFlight. [Copy-ready prompts](Docs/prompts.md) · [MCP server setup and TestFlight results](Docs/mcpserver.md)

## Combined Review

Open **Combined Review** from the dedicated toolbar button beside **AI Analysis**, then choose selected or tagged images as the input.

The default Photo-first workspace pairs the retained overview with concise findings, coverage limits, and optional reviewed-region overlays. **Inspect evidence** opens the supporting crop and observations in the Evidence workspace. You can return to Photo-first while keeping the selected image and region.

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
Compare candidates with Deep Review, Qwen, or Combined Review
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
sharpness, similarity and Deep Review models, into the SwiftUI environment. Views
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
| `photoanalysiskit` | `1.4.0` |
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

The Swift Testing suites cover RAW parsing, focus and sharpness metrics, similarity and semantic search, Deep Review, Qwen responses, downloads, caches, persistence, cancellation, concurrency, and copy workflows.

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

Use only `rebuild.py`. `/graphify` and `graphify update` scan the app folder alone (about 6,200 nodes) and replace the full graph. Don't delete `rebuild.py`, `label_overrides.json`, `licence_semantic.json` or `.graphify_python` in `graphify-out/`: the rebuild needs them and git doesn't track them. If graphify is missing, install it with `uv tool install --upgrade graphifyy`.

## Release

### Release checklist

Run these checks before every release build:

1. **Automated checks.** Run them from a clean worktree on the release commit:

   ```bash
   make verify-ai-import-boundary  # Restricted AI imports
   make release-preflight          # Clean worktree, version and tag, model provenance
   make test-smoke                 # App integration and critical paths
   make test-mcp-release           # MCP helper tests, plus the shared job stores compiled in Release
   ```

2. **Build numbers.** Check that the app and the `RawCullModelDownloader` extension
   have the same `CURRENT_PROJECT_VERSION`. `release.sh` sets both when Xcode
   manages build numbers or when `BUILD_NUMBER` is set. `make build` uses the
   values in the project as they are. `ReleaseMetadataTests`, which runs in
   `make test-full`, fails when the two differ.
3. **Manual smoke test in the app.** The workspace state is now split into separate
   models that views read from the SwiftUI environment (see
   [Architecture](#architecture)). The automated tests do not run the full UI, so
   check these by hand on the built app:
   - Open a catalog. Switch through every view mode: loupe, grid, similarity grid,
     rated grid, comparison grid, AI Analysis and Combined Review. Open and close
     the zoom overlay.
   - Rate, tag and reject a photo. Check that the grid, filters and selection update
     and that the next photo is selected.
   - Group bursts and open the burst workspace. Run Deep Review on one burst.
   - Copy or export one file.
   - Run one end-to-end MCP job from a desktop AI client: catalog approval, analysis,
     and retrieving the ranked burst recommendations.
4. **Build:**

   ```bash
   make build
   ```

`make build` creates the signed, notarized, and stapled app and DMG. It requires the configured Developer ID identity, notarytool keychain profile, and `create-dmg` at `../create-dmg/create-dmg`.

After publishing, verify the downloaded artifact against the generated SHA-256 file:

```bash
make verify-downloaded-dmg \
  DOWNLOADED_DMG=/path/to/downloaded/RawCull.3.4.9.dmg
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
